// Miscellaneous Node: DVM transactions (IHI 0050H B8).
//
// A DVMOp is a write: the MN gives the Requester a DBIDResp, takes the
// 8-byte payload in a NonCopyBackWriteData, sends the two-part SnpDVMOp to
// every RN-F and RN-D except the Requester (B8.2.1 permits leaving it out),
// collects one SnpResp from each, and completes with Comp. Up to dvmMaxOps
// DVMOps run at once, each with its own entry; one entry is always kept for
// a Non-sync, which the forward-progress rule of B8.2.3.1 requires because a
// Request Node may hold its answer to a SnpDVMOp(Sync) until its own Non-sync
// DVMOp completes.
//
// Ordering. A Sync sends its snoops only once every older DVMOp, from any
// source, has collected all its snoop responses; each Request Node answers a
// SnpDVMOp(Sync) only when its earlier DVM operations are complete
// (B8.2.2), so a Sync's Comp follows the completion of every DVM operation
// accepted before it. Comp for a Non-sync is sent only after its own snoop
// responses, not early (B8.2.1.1 permits but does not require early Comp).
//
// Snoops. Both parts of a SnpDVMOp carry the entry index as TxnID, which is
// the MN's own (B8.3.3), and go out back to back. A Request Node is sent at
// most one SnpDVMOp(Non-sync) and one SnpDVMOp(Sync) at a time, the minimum
// every RN-F and RN-D must accept (B8.2.3.2).
//
// Payload (B8.4.2). Part 1 carries REQ.Addr[MPA-1:3] and part 2 the write
// data bits [MPA-1:3], each in the SNP address field with bit 0 marking the
// part; REQ.Addr[3] is zero in a DVMOp, so part 1 needs no change. Range and
// Num travel in FwdNID of part 1, VMID[15:8] in VMIDExt of part 1 (Table
// B8.14, B13.10.44). The exact bit positions of Table B8.14 could not be read
// from the specification text available to this project; see the design
// specification, Section 9.12.
//
// GPT invalidation. A TLBI whose Stage is GPT (Table B8.12) also invalidates
// the GPT cache of the Granule Protection Check: by PA when AddrV is set and
// the invalidation size is one granule, otherwise all of it.
//
// Every input is accepted unconditionally; a DVMOp that finds no entry is
// answered with RetryAck (design specification, Section 9.7).
module chi_mn_dvm #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] MN_NODE_ID = '0,
  // The RN-Fs and RN-Ds a SnpDVMOp goes to.
  parameter int unsigned NUM_DVM_NODES = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    DVM_NODE_IDS [NUM_DVM_NODES] = '{default:'0},
  // Every Requester that may send a DVMOp, for Request Retry.
  parameter int unsigned NUM_REQUESTERS = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    REQUESTER_NODE_IDS [NUM_REQUESTERS] = '{default:'0}
) (
  input  logic clk,
  input  logic resetn,
  input  logic reqInValid,
  output logic reqInReady,
  input  chi_pkg::chi_noc_flit_t reqInFlit,
  input  logic rspInValid,
  output logic rspInReady,
  input  chi_pkg::chi_noc_flit_t rspInFlit,
  input  logic datInValid,
  output logic datInReady,
  input  chi_pkg::chi_noc_flit_t datInFlit,
  output logic snpOutValid,
  input  logic snpOutReady,
  output chi_pkg::chi_noc_flit_t snpOutFlit,
  output logic rspOutValid,
  input  logic rspOutReady,
  output chi_pkg::chi_noc_flit_t rspOutFlit,
  // GPT TLBI towards the Granule Protection Check.
  output logic gptInvalidateAll,
  output logic gptInvalidateByPa,
  output logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gptInvalidateAddr,
  // System coherency (IHI 0050H B15): a node outside the DVM domain gets no
  // new SnpDVMOp, and is idle once none to it is outstanding.
  input  logic [NUM_DVM_NODES-1:0] nodeSnoopable,
  output logic [NUM_DVM_NODES-1:0] nodeIdle,
  output logic idle
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned DEPTH = (CFG.dvmMaxOps > 0) ? CFG.dvmMaxOps : 1;
  localparam int unsigned IDX_W = clog2Min1(DEPTH);
  localparam int unsigned TGT_W = clog2Min1(NUM_DVM_NODES);
  localparam int unsigned RESERVE_W = 16;
  localparam int unsigned RETRY_CREDITS =
    (CFG.retryCredits > 0) ? CFG.retryCredits : 1;
  localparam int unsigned SNP_ADDR_W = CFG.addrW - 3;

  generate
    begin : chi_cfg_check
      initial begin
        if (DEPTH > (1 << CFG.txnIdW))
          $fatal(1, "dvmMaxOps (%0d) does not fit the %0d-bit TxnID the MN uses for DBID and SnpDVMOp",
                 CFG.dvmMaxOps, CFG.txnIdW);
      end
    end
  endgenerate

  typedef struct packed {
    chi_req_flit_t        req;
    logic                 sync;        // DVMType is Synchronization
    logic                 supported;   // a defined DVMType
    logic                 dbidOwed;
    logic                 dataOwed;    // the 8-byte payload has not arrived
    logic [63:0]          payload;
    logic [NUM_DVM_NODES-1:0] toSend;  // SnpDVMOp still to send
    logic [NUM_DVM_NODES-1:0] pending; // SnpResp still owed
    logic                 snoopErr;    // a SnpResp reported NDERR
    logic                 compOwed;
  } mn_entry_t;

  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_dat_flit_t incomingDat;
  mn_entry_t entry [DEPTH];
  mn_entry_t allocEntry;
  logic [DEPTH-1:0] active;
  logic [DEPTH-1:0][DEPTH-1:0] older;

  // Snoops in flight per Request Node.
  logic [NUM_DVM_NODES-1:0] nonSyncOut;
  logic [NUM_DVM_NODES-1:0] syncOut;

  // Output stages.
  logic rspFifoReady;
  logic snpFifoReady;
  logic [1:0] rspFifoCount;
  logic [1:0] snpFifoCount;
  chi_noc_flit_t snpOutPushFlit;

  function automatic logic dvmIsSync(input chi_req_flit_t req);
    return req.addr[13:11] == DVM_TYPE_SYNC;
  endfunction

  function automatic logic [NUM_DVM_NODES-1:0] targetsFor(
    input chi_req_flit_t req
  );
    logic [NUM_DVM_NODES-1:0] targets;
    targets = '1;
    for (int unsigned t = 0; t < NUM_DVM_NODES; t++)
      if (req.srcId == CHI_NODEID_SLOT_W'(DVM_NODE_IDS[t]))
        targets[t] = 1'b0;
    return targets;
  endfunction

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    incomingDat = unpackDatFlit(CFG, datInFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
  end

  // ---------------------------------------------------------------------
  // Admission.
  // ---------------------------------------------------------------------
  logic dropRequest;
  logic isDvm;
  logic incomingSync;
  logic [IDX_W:0] freeCount;
  logic [IDX_W:0] unreservedCount;
  logic freeFound;
  logic [IDX_W-1:0] freeIndex;
  logic resourcesAvailable;
  logic allocValid;
  logic requestHandshake;
  logic retryAck;
  logic [3:0] retryClass;
  logic retryAckWant;
  logic retryHandshake;
  logic retryGrantAllowed;
  logic retryGrantValid;
  logic retryGrantReady;
  logic [CHI_NODEID_SLOT_W-1:0] retryGrantTgtId;
  logic [3:0] retryGrantClass;
  logic [RESERVE_W-1:0] retryCreditsOutstanding;
  logic retryGrantsOwed;

  always_comb begin
    int unsigned free;
    dropRequest = (incomingReq.opcode == REQ_PCRD_RETURN)
                  || (incomingReq.opcode == REQ_PREFETCH_TGT);
    isDvm = incomingReq.opcode == REQ_DVM_OP;
    incomingSync = isDvm && dvmIsSync(incomingReq);
    free = 0;
    freeFound = 1'b0;
    freeIndex = '0;
    for (int unsigned i = 0; i < DEPTH; i++)
      if (!active[i]) begin
        free++;
        if (!freeFound) begin
          freeFound = 1'b1;
          freeIndex = IDX_W'(i);
        end
      end
    freeCount = (IDX_W+1)'(free);
    unreservedCount = (free > int'(retryCreditsOutstanding))
                      ? (IDX_W+1)'(free - int'(retryCreditsOutstanding)) : '0;
    // A request re-sent on a P-Credit uses an entry kept for it. Otherwise a
    // Sync must leave an entry for a Non-sync.
    if (!incomingReq.allowRetry)
      resourcesAvailable = dropRequest || freeFound;
    else
      resourcesAvailable = dropRequest
                           || (int'(unreservedCount) >= (incomingSync ? 2 : 1));
    retryAckWant = reqInValid && !resourcesAvailable && retryAck;
    retryHandshake = retryAckWant && rspFifoReady;
    requestHandshake = reqInValid && resourcesAvailable;
    allocValid = requestHandshake && !dropRequest;
  end

  always_comb begin
    reqInReady = resourcesAvailable || retryHandshake;
  end

  // A grant reserves an entry; a grant for a Sync also leaves one for a
  // Non-sync. Credit type 1 is a Sync, type 0 anything else.
  always_comb begin
    int unsigned needed;
    needed = ((retryGrantClass == 4'd1) ? 2 : 1)
             + ((allocValid && incomingReq.allowRetry) ? 1 : 0);
    retryGrantAllowed = (int'(unreservedCount) >= needed)
                        && (int'(retryCreditsOutstanding) < RETRY_CREDITS);
  end

  chi_retry #(
    .NODEID_W(CHI_NODEID_SLOT_W), .NUM_REQUESTERS(NUM_REQUESTERS),
    .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS),
    .CREDIT_TYPES(2), .OUTSTANDING_W(RESERVE_W)
  ) retry (
    .clk, .resetn, .requestValid(reqInValid),
    .resourcesAvailable, .allowRetry(incomingReq.allowRetry),
    .requestCategory({1'b0, incomingSync}), .requestSrcId(incomingReq.srcId),
    .requestQos(incomingReq.qos),
    .sendRetryAck(retryAck), .retryAckSent(retryHandshake),
    .retryClass,
    .creditUseValid(allocValid && !incomingReq.allowRetry),
    .creditReturnValid(requestHandshake
                       && (incomingReq.opcode == REQ_PCRD_RETURN)),
    .grantAllowed(retryGrantAllowed),
    .grantValid(retryGrantValid), .grantReady(retryGrantReady),
    .grantTgtId(retryGrantTgtId), .grantClass(retryGrantClass),
    .creditsOutstanding(retryCreditsOutstanding),
    .grantsOwed(retryGrantsOwed)
  );

  // The entry a request starts as. Anything but a DVMOp completes with NDERR;
  // a reserved DVMType still takes its payload, then completes with NDERR.
  always_comb begin
    allocEntry = '0;
    allocEntry.req = incomingReq;
    allocEntry.sync = incomingSync;
    allocEntry.supported = isDvm && CFG.dvmEn
                           && (incomingReq.addr[13:11] <= DVM_TYPE_SYNC);
    allocEntry.dbidOwed = isDvm;
    allocEntry.dataOwed = isDvm;
    allocEntry.compOwed = 1'b1;
  end

  // ---------------------------------------------------------------------
  // Snoop issue: one SnpDVMOp part per cycle, both parts of one target back
  // to back, the oldest eligible entry first.
  // ---------------------------------------------------------------------
  logic [DEPTH-1:0] eMaySnoop;
  logic [DEPTH-1:0] eOlderBusy;
  // For the bound assertions.
  logic [DEPTH-1:0] activeSync;
  logic snpIsSync;
  logic snpValid;
  logic [IDX_W-1:0] snpEntry;
  logic [TGT_W-1:0] snpTarget;
  logic snpPartTwo;
  logic snpHold;
  logic [IDX_W-1:0] snpHoldEntry;
  logic [TGT_W-1:0] snpHoldTarget;
  logic snpFire;

  always_comb begin
    for (int unsigned i = 0; i < DEPTH; i++) begin
      logic olderBusy;
      olderBusy = 1'b0;
      for (int unsigned j = 0; j < DEPTH; j++)
        if ((j != i) && active[j] && older[i][j]
            && ((entry[j].toSend != '0) || (entry[j].pending != '0)
                || entry[j].dataOwed))
          olderBusy = 1'b1;
      eOlderBusy[i] = olderBusy;
      activeSync[i] = active[i] && entry[i].sync;
      eMaySnoop[i] = active[i] && entry[i].supported && !entry[i].dataOwed
                     && (entry[i].toSend != '0)
                     && (!entry[i].sync || !olderBusy);
    end

    snpValid = 1'b0;
    snpEntry = '0;
    snpTarget = '0;
    if (snpHold) begin
      // Part 2 follows part 1 to the same target.
      snpValid = 1'b1;
      snpEntry = snpHoldEntry;
      snpTarget = snpHoldTarget;
    end else begin
      for (int unsigned i = 0; i < DEPTH; i++) begin
        // Oldest first: an entry with no older eligible entry.
        logic olderEligible;
        olderEligible = 1'b0;
        for (int unsigned j = 0; j < DEPTH; j++)
          if ((j != i) && eMaySnoop[j] && older[i][j])
            olderEligible = 1'b1;
        if (!snpValid && eMaySnoop[i] && !olderEligible)
          for (int unsigned t = 0; t < NUM_DVM_NODES; t++)
            if (!snpValid && entry[i].toSend[t] && nodeSnoopable[t]
                && !(entry[i].sync ? syncOut[t] : nonSyncOut[t])) begin
              snpValid = 1'b1;
              snpEntry = IDX_W'(i);
              snpTarget = TGT_W'(t);
            end
      end
    end
    snpPartTwo = snpHold;
    snpFire = snpValid && snpFifoReady;
    snpIsSync = entry[snpEntry].sync;
  end

  always_comb begin
    chi_snp_flit_t snoop;
    mn_entry_t e;
    logic [SNP_ADDR_W-1:0] part;
    e = entry[snpEntry];
    snoop = '0;
    snoop.qos = e.req.qos;
    snoop.srcId = MN_NODE_ID;
    snoop.txnId = CHI_TXNID_FLIT_W'(snpEntry);
    snoop.opcode = SNP_DVM_OP;
    // PAS, RetToSrc and DoNotGoToSD are zero in a SnpDVMOp (B8.3.3).
    snoop.pas = PAS_SECURE;
    snoop.doNotGoToSd = 1'b0;
    snoop.retToSrc = 1'b0;
    if (!snpPartTwo) begin
      part = e.req.addr[CFG.addrW-1:3];
      part[0] = 1'b0;
      // Range and Num in FwdNID, VMID[15:8] in VMIDExt (Table B8.14,
      // B13.10.44).
      snoop.fwdNidOrPbha = CHI_MAX_NODEID_W'({e.req.addr[42], e.payload[3],
                                              e.req.addr[2:0], e.req.addr[41]});
      snoop.fwdTxnIdOrStashLpidOrVmidExt = '0;
      snoop.fwdTxnIdOrStashLpidOrVmidExt[7:0] = e.payload[63:56];
    end else begin
      part = e.payload[SNP_ADDR_W+2:3];
      part[0] = 1'b1;
    end
    snoop.addr = (CHI_MAX_ADDR_W-3)'(part);
    snpOutPushFlit = '0;
    snpOutPushFlit.channel = CHI_CHANNEL_SNP;
    snpOutPushFlit.qos = snoop.qos;
    snpOutPushFlit.targetNodeId = DVM_NODE_IDS[snpTarget];
    snpOutPushFlit.payload[CHI_MAX_SNP_FLIT_W-1:0] = packSnpFlit(CFG, snoop);
  end


  // ---------------------------------------------------------------------
  // Responses to Requesters: RetryAck, PCrdGrant, then DBIDResp or Comp of
  // one entry in rotation.
  // ---------------------------------------------------------------------
  logic [DEPTH-1:0] dbidReady;
  logic [DEPTH-1:0] compReady;
  logic rspEntryValid;
  logic [IDX_W-1:0] rspEntry;
  logic [IDX_W-1:0] rspPointer;
  logic rspGrantSend;
  logic rspEntrySend;
  logic rspPushValid;
  chi_noc_flit_t rspPushFlit;

  always_comb begin
    int unsigned candidate;
    for (int unsigned i = 0; i < DEPTH; i++) begin
      dbidReady[i] = active[i] && entry[i].dbidOwed;
      compReady[i] = active[i] && entry[i].compOwed && !entry[i].dbidOwed
                     && !entry[i].dataOwed && (entry[i].toSend == '0)
                     && (entry[i].pending == '0);
    end
    rspEntryValid = 1'b0;
    rspEntry = '0;
    for (int unsigned offset = 0; offset < DEPTH; offset++) begin
      candidate = (int'(rspPointer) + offset) % DEPTH;
      if (!rspEntryValid && (dbidReady[candidate] || compReady[candidate])) begin
        rspEntryValid = 1'b1;
        rspEntry = IDX_W'(candidate);
      end
    end
    rspGrantSend = !retryAckWant && retryGrantValid && rspFifoReady;
    rspEntrySend = !retryAckWant && !retryGrantValid && rspEntryValid
                   && rspFifoReady;
    retryGrantReady = rspGrantSend;
  end

  always_comb begin
    chi_rsp_flit_t response;
    mn_entry_t e;
    e = entry[rspEntry];
    response = '0;
    response.srcId = MN_NODE_ID;
    if (retryAckWant) begin
      response.qos = incomingReq.qos;
      response.tgtId = incomingReq.srcId;
      response.txnId = incomingReq.txnId;
      response.opcode = RSP_RETRY_ACK;
      response.pCrdType = retryClass;
    end else if (retryGrantValid) begin
      response.tgtId = retryGrantTgtId;
      response.opcode = RSP_PCRD_GRANT;
      response.pCrdType = retryGrantClass;
    end else begin
      response.qos = e.req.qos;
      response.tgtId = e.req.srcId;
      response.txnId = e.req.txnId;
      response.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(rspEntry);
      if (dbidReady[rspEntry]) begin
        response.opcode = RSP_DBID_RESP;
      end else begin
        response.opcode = RSP_COMP;
        response.respErr = (!e.supported || e.snoopErr) ? RESP_ERR_NDERR
                                                         : RESP_ERR_OK;
      end
    end
    rspPushValid = retryAckWant || retryGrantValid || rspEntryValid;
    rspPushFlit = '0;
    rspPushFlit.channel = CHI_CHANNEL_RSP;
    rspPushFlit.qos = response.qos;
    rspPushFlit.targetNodeId = response.tgtId;
    rspPushFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, response);
  end

  // ---------------------------------------------------------------------
  // Inputs: always accepted.
  // ---------------------------------------------------------------------
  logic snoopRspValid;
  logic [IDX_W-1:0] snoopRspEntry;
  logic [TGT_W-1:0] snoopRspTarget;
  logic snoopRspKnown;
  logic payloadValid;
  logic [IDX_W-1:0] payloadEntry;

  always_comb begin
    rspInReady = 1'b1;
    datInReady = 1'b1;
  end

  always_comb begin
    snoopRspKnown = 1'b0;
    snoopRspTarget = '0;
    for (int unsigned t = 0; t < NUM_DVM_NODES; t++)
      if (incomingRsp.srcId == CHI_NODEID_SLOT_W'(DVM_NODE_IDS[t])) begin
        snoopRspKnown = 1'b1;
        snoopRspTarget = TGT_W'(t);
      end
    snoopRspEntry = IDX_W'(incomingRsp.txnId);
    snoopRspValid = rspInValid && (incomingRsp.opcode == RSP_SNP_RESP)
                    && snoopRspKnown && (int'(incomingRsp.txnId) < DEPTH)
                    && entry[snoopRspEntry].pending[snoopRspTarget];
    payloadEntry = IDX_W'(incomingDat.txnId);
    payloadValid = datInValid
                   && (incomingDat.opcode == DAT_NON_COPY_BACK_WR_DATA)
                   && (int'(incomingDat.txnId) < DEPTH)
                   && entry[payloadEntry].dataOwed;
  end

  // GPT TLBI: DVMType TLBI with Stage GPT (Table B8.12). PA[51:12] and the
  // invalidation size travel in the write data (Table B8.10, B8.4.3.3).
  always_comb begin
    chi_req_flit_t req;
    logic gptTlbi;
    req = entry[payloadEntry].req;
    gptTlbi = payloadValid && entry[payloadEntry].supported
              && (req.addr[13:11] == DVM_TYPE_TLBI) && (req.addr[39:38] == 2'b11);
    gptInvalidateByPa = gptTlbi && req.addr[4]
                        && (incomingDat.data[9:6] == 4'b0000);
    gptInvalidateAll = gptTlbi && !gptInvalidateByPa;
    gptInvalidateAddr = '0;
    gptInvalidateAddr[CHI_MAX_ADDR_W-1:12] =
      (CHI_MAX_ADDR_W-12)'(incomingDat.data[49:10]);
  end

  // ---------------------------------------------------------------------
  // Output stages.
  // ---------------------------------------------------------------------
  chi_flit_fifo rsp_fifo (
    .clk, .resetn, .pushValid(rspPushValid), .pushReady(rspFifoReady),
    .pushFlit(rspPushFlit), .outValid(rspOutValid), .outReady(rspOutReady),
    .outFlit(rspOutFlit), .count(rspFifoCount)
  );
  chi_flit_fifo snp_fifo (
    .clk, .resetn, .pushValid(snpValid), .pushReady(snpFifoReady),
    .pushFlit(snpOutPushFlit), .outValid(snpOutValid), .outReady(snpOutReady),
    .outFlit(snpOutFlit), .count(snpFifoCount)
  );

  always_comb begin
    idle = (active == '0) && (rspFifoCount == '0) && (snpFifoCount == '0)
           && !retryGrantsOwed && (retryCreditsOutstanding == '0);
  end

  // ---------------------------------------------------------------------
  // State.
  // ---------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < DEPTH; i++)
        entry[i] <= '0;
      active <= '0;
      older <= '0;
      nonSyncOut <= '0;
      syncOut <= '0;
      snpHold <= 1'b0;
      snpHoldEntry <= '0;
      snpHoldTarget <= '0;
      rspPointer <= '0;
    end else begin
      if (allocValid) begin
        entry[freeIndex] <= allocEntry;
        active[freeIndex] <= 1'b1;
        older[freeIndex] <= active;
        for (int unsigned i = 0; i < DEPTH; i++)
          older[i][freeIndex] <= 1'b0;
      end

      if (payloadValid) begin
        entry[payloadEntry].dataOwed <= 1'b0;
        entry[payloadEntry].payload <= incomingDat.data[63:0];
        if (entry[payloadEntry].supported)
          entry[payloadEntry].toSend <= targetsFor(entry[payloadEntry].req)
                                        & nodeSnoopable;
      end

      if (snpFire) begin
        if (!snpPartTwo) begin
          snpHold <= 1'b1;
          snpHoldEntry <= snpEntry;
          snpHoldTarget <= snpTarget;
          if (entry[snpEntry].sync)
            syncOut[snpTarget] <= 1'b1;
          else
            nonSyncOut[snpTarget] <= 1'b1;
        end else begin
          snpHold <= 1'b0;
          entry[snpEntry].toSend[snpTarget] <= 1'b0;
          entry[snpEntry].pending[snpTarget] <= 1'b1;
        end
      end

      if (snoopRspValid) begin
        entry[snoopRspEntry].pending[snoopRspTarget] <= 1'b0;
        if (incomingRsp.respErr == RESP_ERR_NDERR)
          entry[snoopRspEntry].snoopErr <= 1'b1;
        if (entry[snoopRspEntry].sync)
          syncOut[snoopRspTarget] <= 1'b0;
        else
          nonSyncOut[snoopRspTarget] <= 1'b0;
      end

      if (rspEntrySend) begin
        if (dbidReady[rspEntry]) begin
          entry[rspEntry].dbidOwed <= 1'b0;
        end else begin
          entry[rspEntry].compOwed <= 1'b0;
          active[rspEntry] <= 1'b0;
        end
        rspPointer <= (int'(rspEntry) == (DEPTH - 1)) ? '0 : (rspEntry + 1'b1);
      end

      // A SnpDVMOp not yet sent to a node that has left the DVM domain is
      // dropped; a part 2 still follows its part 1.
      for (int unsigned t = 0; t < NUM_DVM_NODES; t++)
        if (!nodeSnoopable[t])
          for (int unsigned i = 0; i < DEPTH; i++)
            entry[i].toSend[t] <= 1'b0;
    end
  end

  always_comb
    for (int unsigned t = 0; t < NUM_DVM_NODES; t++)
      nodeIdle[t] = !syncOut[t] && !nonSyncOut[t];
endmodule
