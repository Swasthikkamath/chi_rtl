module chi_hnf_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] SN_NODE_ID = '0,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    RNF_NODE_IDS [NUM_RNF] = '{default:'0},
  parameter bit COMBINED_COMP_DBID = 1'b1,
  parameter bit COMBINED_COMP_STASH_DONE = 1'b1
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
  output logic reqOutValid,
  input  logic reqOutReady,
  output chi_pkg::chi_noc_flit_t reqOutFlit,
  output logic rspOutValid,
  input  logic rspOutReady,
  output chi_pkg::chi_noc_flit_t rspOutFlit,
  output logic snpOutValid,
  input  logic snpOutReady,
  output chi_pkg::chi_noc_flit_t snpOutFlit,
  output logic datOutValid,
  input  logic datOutReady,
  output chi_pkg::chi_noc_flit_t datOutFlit,
  output logic idle
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned POS_DEPTH = (CFG.posEntries > 0) ? CFG.posEntries : 1;
  localparam int unsigned RETRY_RECORDS =
    (CFG.retryRecords > 0) ? CFG.retryRecords : 1;
  localparam int unsigned DAT_BYTES = CFG.dataW / 8;
  localparam int unsigned DAT_OFF_W = clog2Min1(DAT_BYTES);

  typedef enum logic [4:0] {
    HNF_IDLE, HNF_SNOOP_START, HNF_SNOOP_WAIT, HNF_REQ_SEND,
    HNF_WAIT_RESPONSE, HNF_WAIT_COMP_ACK, HNF_BACKINV_START,
    HNF_BACKINV_WAIT, HNF_ATOMIC_DBID, HNF_ATOMIC_OPERAND,
    HNF_ATOMIC_READ, HNF_ATOMIC_INITIAL, HNF_ATOMIC_WRITE,
    HNF_ATOMIC_WDATA, HNF_ATOMIC_WCOMP, HNF_ATOMIC_RETURN,
    HNF_ORDER_RECEIPT, HNF_DMT_RESP, HNF_STASH_COMP, HNF_STASH_DONE,
    HNF_PULL_REQ, HNF_PULL_DATA
  } hnf_state_e;
  hnf_state_e state;

  chi_req_flit_t incomingReq;
  chi_req_flit_t activeReq;
  chi_rsp_flit_t incomingRsp;
  chi_dat_flit_t incomingDat;
  chi_req_flit_t downstreamReq;
  chi_rsp_flit_t responseFlit;
  chi_dat_flit_t requesterDat;
  logic [CFG.addrW-7:0] incomingLine;
  logic coherentRequest;
  logic activeCoherent;
  logic activeWrite;
  logic activeCmo;
  logic cmoWrite;
  logic cmoCombined;
  logic cmoSnoop;
  logic cmoPersist;
  logic [2:0] cmoCategory;
  logic cmoCompletionPending;
  logic cmoPersistPending;
  logic cmoDone;

  logic posAllocReady;
  logic [clog2Min1(POS_DEPTH)-1:0] posAllocIndex;
  logic [clog2Min1(POS_DEPTH)-1:0] activePosIndex;
  logic posFree;
  logic [POS_DEPTH-1:0] posActive;
  logic [POS_DEPTH-1:0] posReadyToFree;
  logic [POS_DEPTH-1:0][CFG.addrW-7:0] posLine;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] posRequester [POS_DEPTH];
  logic [CFG.txnIdW-1:0] posTxn [POS_DEPTH];
  chi_req_opcode_e posOpcode [POS_DEPTH];
  logic [2:0] posLifecycle [POS_DEPTH];
  logic sameAddressBusy;

  logic sfHit;
  logic [NUM_RNF-1:0] sfSharers;
  logic sfPrecise;
  logic sfHasOwner;
  logic [clog2Min1(NUM_RNF)-1:0] sfOwner;
  logic sfUpdate;
  logic sfUpdateReady;
  logic [NUM_RNF-1:0] sfUpdateSharers;
  logic sfInvalidate;
  logic sfBackInvValid;
  logic sfBackInvReady;
  logic [CFG.addrW-7:0] sfBackInvLine;
  logic [NUM_RNF-1:0] sfBackInvSharers;
  logic sfBackInvDone;

  logic snpStart;
  logic snpStartReady;
  logic [NUM_RNF-1:0] snpStartSharers;
  logic [CFG.addrW-7:0] snpStartLine;
  chi_snp_opcode_e snpStartOpcode;
  logic [CFG.txnIdW-1:0] snpStartTxn;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] snpFwdNid;
  logic [CFG.txnIdW-1:0] snpFwdTxn;
  logic snpRetToSrc;
  logic snpBusy;
  logic snpDone;
  logic snpRspReady;

  logic dctEligible;
  logic dctFallback;
  chi_snp_opcode_e dctOpcode;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] dctFwdNid;
  logic [CFG.txnIdW-1:0] dctFwdTxn;
  logic dctRetToSrc;

  logic retryAccept;
  logic retryAck;
  logic [3:0] retryClass;
  logic [1:0] retryCategory;
  logic retryRecordFull;
  logic retryAckSend;
  logic retryGrantValid;
  logic retryGrantReady;
  logic retryGrantSend;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] retryGrantTgtId;
  logic [3:0] retryGrantClass;
  logic retryCreditsPending;
  logic [7:0] retryPending [CHI_CREDIT_TYPES];
  logic [7:0] retryOutstanding [CHI_CREDIT_TYPES];
  chi_rsp_flit_t grantFlit;
  logic resourcesAvailable;
  logic droppedRequest;
  logic rspOutBusy;
  logic hazardBlocked;
  logic hazardLine;
  logic hazardOrder;
  logic [POS_DEPTH-1:0] activeOrdered;
  logic requestHandshake;
  logic retryHandshake;
  logic activeNeedsSnoop;
  logic exclReserveReady;
  logic exclOkay;
  logic activeExclOkay;
  logic activeNeedPersist;
  logic activeGotComp;
  logic activeGotPersist;

  logic dmtEligible;
  logic dmtSeparateResponse;
  logic [CHI_NODEID_SLOT_W-1:0] dmtReturnNid;
  logic [CHI_TXNID_FLIT_W-1:0] dmtReturnTxnId;
  logic dwtEligible;
  logic dwtDoDwt;
  logic [CHI_NODEID_SLOT_W-1:0] dwtReturnNid;
  logic [CHI_TXNID_FLIT_W-1:0] dwtReturnTxnId;
  logic activeDmt;
  logic activeDmtSeparate;
  logic activeDwt;
  logic orderedReceiptRequired;
  chi_rsp_flit_t orderResponse;

  logic stashIsStash;
  logic stashIndependent;
  logic stashSeparateDone;
  logic stashTargetValid;
  logic [NUM_RNF-1:0] stashTargetMask;
  chi_snp_opcode_e stashTargetSnoop;
  logic stashLpidValid;
  logic [chi_cfg_pkg::CHI_MAX_LPID_W-1:0] stashLpid;
  chi_req_opcode_e stashPullOpcode;
  chi_resp_e stashPullResp;
  logic stashUnique;
  logic activeStash;
  logic activeStashUnique;
  logic activeStashIndependent;
  logic activeStashSeparate;
  logic [NUM_RNF-1:0] activeStashTargetMask;
  chi_snp_opcode_e activeStashSnoop;
  logic activeStashLpidValid;
  logic [chi_cfg_pkg::CHI_MAX_LPID_W-1:0] activeStashLpid;
  chi_resp_e activeStashPullResp;
  logic dataPullValid;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] dataPullTarget;
  logic [chi_cfg_pkg::CHI_RSP_DBID_SLOT_W-1:0] dataPullTxnId;
  logic stashPullPending;
  logic stashDirUpdate;
  logic sfUpdateHasOwner;
  logic [clog2Min1(NUM_RNF)-1:0] sfUpdateOwner;
  chi_req_flit_t pullReq;
  chi_dat_flit_t pullDat;
  chi_rsp_flit_t stashResponse;

  logic atomicRequest;
  logic activeAtomic;
  logic atomicOpcodeValid;
  logic atomicReturnsData;
  logic atomicUpdateEnable;
  logic [2:0] atomicOperandSize;
  logic [DAT_OFF_W-1:0] atomicByteOffset;
  logic [63:0] atomicTransactionData;
  logic [63:0] atomicCompareData;
  logic [63:0] atomicInitialWord;
  logic [63:0] atomicUpdateWord;
  logic [63:0] atomicOriginalWord;
  logic [CFG.dataW-1:0] atomicOperandBuffer;
  logic [CFG.dataW-1:0] atomicInitialBuffer;
  logic atomicInitialFromSnoop;
  logic atomicDbidSeen;
  logic atomicCompSeen;
  logic atomicDataSent;
  chi_req_flit_t atomicDownstreamReq;
  chi_dat_flit_t atomicDownstreamDat;
  chi_dat_flit_t atomicReturnDat;
  chi_rsp_flit_t atomicResponse;
  logic atomicStateActive;

  function automatic logic [63:0] extractWord(
    input logic [CFG.dataW-1:0] bus,
    input logic [DAT_OFF_W-1:0] byteOffset
  );
    logic [63:0] result;
    int unsigned index;
    result = '0;
    for (int unsigned b = 0; b < 8; b++) begin
      index = int'(byteOffset) + b;
      if (index < DAT_BYTES)
        result[b*8 +: 8] = bus[index*8 +: 8];
    end
    return result;
  endfunction

  function automatic logic [CFG.dataW-1:0] insertWord(
    input logic [CFG.dataW-1:0] bus,
    input logic [DAT_OFF_W-1:0] byteOffset,
    input logic [63:0] value,
    input logic [2:0] operandSize
  );
    logic [CFG.dataW-1:0] result;
    int unsigned index;
    int unsigned validBytes;
    result = bus;
    validBytes = 1 << operandSize;
    for (int unsigned b = 0; b < 8; b++) begin
      index = int'(byteOffset) + b;
      if ((b < validBytes) && (index < DAT_BYTES))
        result[index*8 +: 8] = value[b*8 +: 8];
    end
    return result;
  endfunction

  function automatic logic [CFG.dataW/8-1:0] operandByteEnables(
    input logic [DAT_OFF_W-1:0] byteOffset,
    input logic [2:0] operandSize
  );
    logic [CFG.dataW/8-1:0] result;
    int unsigned index;
    int unsigned validBytes;
    result = '0;
    validBytes = 1 << operandSize;
    for (int unsigned b = 0; b < 8; b++) begin
      index = int'(byteOffset) + b;
      if ((b < validBytes) && (index < DAT_BYTES))
        result[index] = 1'b1;
    end
    return result;
  endfunction

  function automatic logic isCoherent(input chi_req_opcode_e op);
    return (op == REQ_READ_SHARED) || (op == REQ_READ_CLEAN)
           || (op == REQ_READ_UNIQUE) || (op == REQ_READ_NOT_SHARED_DIRTY)
           || (op == REQ_READ_PREFER_UNIQUE) || (op == REQ_CLEAN_SHARED)
           || (op == REQ_CLEAN_INVALID) || (op == REQ_MAKE_INVALID)
           || (op == REQ_CLEAN_UNIQUE) || (op == REQ_MAKE_UNIQUE);
  endfunction

  function automatic logic isAtomicOpcode(input chi_req_opcode_e op);
    return ((op >= REQ_ATOMIC_STORE_ADD) && (op <= REQ_ATOMIC_LOAD_UMIN))
           || (op == REQ_ATOMIC_SWAP) || (op == REQ_ATOMIC_COMPARE);
  endfunction

  function automatic logic isWrite(input chi_req_opcode_e op);
    return (op inside {REQ_WRITE_EVICT_FULL, REQ_WRITE_CLEAN_FULL,
                       REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_FULL,
                       REQ_WRITE_BACK_PTL, REQ_WRITE_BACK_FULL,
                       REQ_WRITE_NO_SNP_PTL, REQ_WRITE_NO_SNP_FULL,
                       REQ_WRITE_UNIQUE_ZERO, REQ_WRITE_NO_SNP_ZERO,
                       REQ_WRITE_UNIQUE_FULL_STASH,
                       REQ_WRITE_UNIQUE_PTL_STASH});
  endfunction

  function automatic logic [NUM_RNF-1:0] requesterBit(
    input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] nodeId
  );
    logic [NUM_RNF-1:0] result;
    result = '0;
    for (int unsigned i = 0; i < NUM_RNF; i++)
      if (nodeId == RNF_NODE_IDS[i])
        result[i] = 1'b1;
    return result;
  endfunction

  function automatic logic [clog2Min1(NUM_RNF)-1:0] requesterIndex(
    input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] nodeId
  );
    logic [clog2Min1(NUM_RNF)-1:0] result;
    result = '0;
    for (int unsigned i = 0; i < NUM_RNF; i++)
      if (nodeId == RNF_NODE_IDS[i])
        result = i[clog2Min1(NUM_RNF)-1:0];
    return result;
  endfunction

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    incomingDat = unpackDatFlit(CFG, datInFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    incomingLine = incomingReq.addr[CFG.addrW-1:6];
    coherentRequest = isCoherent(incomingReq.opcode);
    atomicRequest = CFG.atomicEn && isAtomicOpcode(incomingReq.opcode);
  end

  // Resource evaluation sits in its own block because the retry tracker turns
  // it into the RetryAck decision that the output block below consumes.
  always_comb begin
    // PCrdReturn carries no transaction, and PrefetchTgt has no response and
    // must never be retried, so both are accepted and discarded here
    // (IHI 0050H B2.5.6, B4.2.6.2).
    droppedRequest = (incomingReq.opcode == REQ_PCRD_RETURN)
                     || (incomingReq.opcode == REQ_PREFETCH_TGT);
    resourcesAvailable = droppedRequest
                         || ((state == HNF_IDLE) && posAllocReady
                             && !hazardBlocked && !sfBackInvValid);
    // The response channel belongs to the active transaction in these states,
    // so neither a RetryAck nor a PCrdGrant can use it.
    rspOutBusy = (state == HNF_WAIT_RESPONSE) || (state == HNF_ORDER_RECEIPT)
                 || (state == HNF_DMT_RESP) || (state == HNF_ATOMIC_DBID)
                 || (state == HNF_ATOMIC_RETURN) || (state == HNF_STASH_COMP)
                 || (state == HNF_STASH_DONE);
  end

  // Everything this block drives is a flit or a valid, so none of it may look
  // at the ready it is paired with. The response channel is shared by the
  // active transaction, a RetryAck and a PCrdGrant, and that contention is
  // resolved here without the ready.
  always_comb begin
    retryAckSend = reqInValid && !resourcesAvailable && retryAck && !rspOutBusy;
    retryGrantSend = retryGrantValid && !retryAckSend && !rspOutBusy;
    requestHandshake = reqInValid && resourcesAvailable;
    idle = (state == HNF_IDLE) && !sfBackInvValid;

    downstreamReq = activeReq;
    downstreamReq.tgtId = SN_NODE_ID;
    downstreamReq.srcId = HN_NODE_ID;
    // A direct transfer names the Requester in the downstream request and
    // uses a Home-unique TxnID that the Subordinate reflects as DBID.
    if (activeDmt || activeDwt) begin
      downstreamReq.txnId = CHI_TXNID_FLIT_W'(activePosIndex);
      downstreamReq.returnNidOrStashNidOrDataTarget = activeReq.srcId;
      downstreamReq.returnTxnIdOrStashLpid = activeReq.txnId;
      downstreamReq.snpAttrOrDoDwt = activeDwt;
    end
    reqOutFlit = '0;
    reqOutFlit.channel = CHI_CHANNEL_REQ;
    reqOutFlit.targetNodeId = SN_NODE_ID;
    reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] =
      packReqFlit(CFG, downstreamReq);
    reqOutValid = state == HNF_REQ_SEND;

    responseFlit = incomingRsp;
    responseFlit.tgtId = activeReq.srcId;
    responseFlit.srcId = HN_NODE_ID;
    responseFlit.txnId = activeReq.txnId;
    // With DWT the Subordinate has already sent DBIDResp to the Requester, so
    // the Home must forward only the completion.
    if (COMBINED_COMP_DBID && activeWrite && !activeDwt
        && (incomingRsp.opcode == RSP_COMP))
      responseFlit.opcode = RSP_COMP_DBID_RESP;
    if (activeReq.exclOrSnoopMeOrCah && activeExclOkay)
      responseFlit.respErr = RESP_ERR_EXOK;
    rspOutFlit = '0;
    rspOutFlit.channel = CHI_CHANNEL_RSP;
    rspOutFlit.targetNodeId = activeReq.srcId;
    rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
      packRspFlit(CFG, responseFlit);
    rspOutValid = 1'b0;

    requesterDat = incomingDat;
    requesterDat.tgtId = (incomingDat.srcId == activeReq.srcId)
                         ? SN_NODE_ID : activeReq.srcId;
    requesterDat.srcId = HN_NODE_ID;
    requesterDat.txnId = activeReq.txnId;
    datOutFlit = '0;
    datOutFlit.channel = CHI_CHANNEL_DAT;
    datOutFlit.targetNodeId = requesterDat.tgtId;
    datOutFlit.payload = packDatFlit(CFG, requesterDat);
    datOutValid = 1'b0;

    if ((state == HNF_WAIT_RESPONSE) && rspInValid
        && (incomingRsp.opcode != RSP_SNP_RESP)
        && (incomingRsp.opcode != RSP_SNP_RESP_FWDED))
      rspOutValid = 1'b1;
    if ((state == HNF_WAIT_RESPONSE) && datInValid)
      datOutValid = 1'b1;

    if ((state == HNF_ORDER_RECEIPT) || (state == HNF_DMT_RESP)) begin
      rspOutValid = 1'b1;
      rspOutFlit.targetNodeId = activeReq.srcId;
      rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
        packRspFlit(CFG, orderResponse);
    end

    if ((state == HNF_STASH_COMP) || (state == HNF_STASH_DONE)) begin
      rspOutValid = 1'b1;
      rspOutFlit.targetNodeId = activeReq.srcId;
      rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
        packRspFlit(CFG, stashResponse);
    end

    if (state == HNF_PULL_REQ) begin
      reqOutValid = 1'b1;
      reqOutFlit.targetNodeId = SN_NODE_ID;
      reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] = packReqFlit(CFG, pullReq);
    end

    if (state == HNF_PULL_DATA) begin
      datOutValid = datInValid && (incomingDat.opcode == DAT_COMP_DATA);
      datOutFlit.targetNodeId = dataPullTarget;
      datOutFlit.payload = packDatFlit(CFG, pullDat);
    end

    if (retryAckSend) begin
      responseFlit = '0;
      responseFlit.tgtId = incomingReq.srcId;
      responseFlit.srcId = HN_NODE_ID;
      responseFlit.txnId = incomingReq.txnId;
      responseFlit.opcode = RSP_RETRY_ACK;
      responseFlit.pCrdType = retryClass;
      rspOutFlit.targetNodeId = incomingReq.srcId;
      rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
        packRspFlit(CFG, responseFlit);
      rspOutValid = 1'b1;
    end

    if (retryGrantSend) begin
      rspOutValid = 1'b1;
      rspOutFlit.targetNodeId = retryGrantTgtId;
      rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, grantFlit);
    end

    if (atomicStateActive) begin
      rspOutValid = (state == HNF_ATOMIC_DBID)
                    || ((state == HNF_ATOMIC_RETURN) && !atomicReturnsData);
      rspOutFlit.targetNodeId = activeReq.srcId;
      rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] =
        packRspFlit(CFG, atomicResponse);

      reqOutValid = atomicOpcodeValid
                    && ((state == HNF_ATOMIC_READ)
                        || ((state == HNF_ATOMIC_WRITE)
                            && atomicUpdateEnable));
      reqOutFlit.targetNodeId = SN_NODE_ID;
      reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] =
        packReqFlit(CFG, atomicDownstreamReq);

      datOutValid = (state == HNF_ATOMIC_WDATA)
                    || ((state == HNF_ATOMIC_RETURN) && atomicReturnsData);
      if (state == HNF_ATOMIC_WDATA) begin
        datOutFlit.targetNodeId = SN_NODE_ID;
        datOutFlit.payload = packDatFlit(CFG, atomicDownstreamDat);
      end else begin
        datOutFlit.targetNodeId = activeReq.srcId;
        datOutFlit.payload = packDatFlit(CFG, atomicReturnDat);
      end
    end
  end

  // The ready outputs are the only place a downstream ready is consumed. They
  // are kept in a block of their own so that the flits and valids above stay
  // independent of them, which is what makes the ready/valid handshake on
  // every channel free of a combinational loop.
  always_comb begin
    // RetryAck is optional: when the retry record table is full the request is
    // held with back-pressure instead, which keeps the credit accounting exact.
    reqInReady = resourcesAvailable || (retryAckSend && rspOutReady);
    retryHandshake = retryAckSend && rspOutReady;
    retryGrantReady = retryGrantSend && rspOutReady;
    rspInReady = 1'b0;
    datInReady = 1'b0;

    if ((state == HNF_WAIT_RESPONSE) && rspInValid
        && (incomingRsp.opcode != RSP_SNP_RESP)
        && (incomingRsp.opcode != RSP_SNP_RESP_FWDED))
      rspInReady = rspOutReady;
    if ((state == HNF_WAIT_RESPONSE) && datInValid)
      datInReady = datOutReady;
    if ((state == HNF_SNOOP_WAIT) || (state == HNF_BACKINV_WAIT))
      rspInReady = snpRspReady;
    // A snoop that invalidates a dirty peer copy supplies the value the
    // atomic operates on, which removes the downstream read.
    if ((state == HNF_SNOOP_WAIT) && activeAtomic)
      datInReady = 1'b1;
    if (state == HNF_PULL_DATA)
      datInReady = datOutReady;
    // A ReadReceipt from the Subordinate is optional and carries no state the
    // Home needs once the read has been forwarded, so it is always drained.
    if (rspInValid && (incomingRsp.opcode == RSP_READ_RECEIPT))
      rspInReady = 1'b1;
    if (state == HNF_WAIT_COMP_ACK)
      rspInReady = rspInValid && (incomingRsp.opcode == RSP_COMP_ACK)
                   && (incomingRsp.srcId == activeReq.srcId);
    if (atomicStateActive) begin
      datInReady = (state == HNF_ATOMIC_OPERAND)
                   || (state == HNF_ATOMIC_INITIAL);
      rspInReady = (state == HNF_ATOMIC_WCOMP);
    end
  end

  chi_cmo cmo_decode (
    .clk, .resetn, .opcode(incomingReq.opcode),
    .startValid(requestHandshake), .completionValid(
      (state == HNF_WAIT_RESPONSE) && rspInValid && rspInReady
      && ((incomingRsp.opcode == RSP_COMP)
          || (incomingRsp.opcode == RSP_COMP_DBID_RESP)
          || (incomingRsp.opcode == RSP_COMP_CMO)
          || (incomingRsp.opcode == RSP_COMP_PERSIST))),
    .persistValid((state == HNF_WAIT_RESPONSE) && rspInValid && rspInReady
                  && ((incomingRsp.opcode == RSP_PERSIST)
                      || (incomingRsp.opcode == RSP_COMP_PERSIST))),
    .isCmo(activeCmo), .isWrite(cmoWrite),
    .combinedWriteCmo(cmoCombined), .requiresSnoopCompletion(cmoSnoop),
    .requiresPersist(cmoPersist), .category(cmoCategory),
    .completionPending(cmoCompletionPending),
    .persistPending(cmoPersistPending), .done(cmoDone)
  );

  always_comb begin
    activeOrdered = '0;
    if (activeReq.order != ORDER_NONE)
      activeOrdered = posActive;
  end

  chi_hazard #(.CFG(CFG), .DEPTH(POS_DEPTH)) hazard (
    .requestLineAddr(incomingLine), .requestOrder(incomingReq.order),
    .active(posActive), .activeLineAddr(posLine), .activeOrdered,
    .lineHazard(hazardLine), .orderHazard(hazardOrder), .blocked(hazardBlocked)
  );

  chi_excl_mon #(
    .CFG(CFG), .MONITORS((CFG.exclMonitors > 0) ? CFG.exclMonitors : 1)
  ) exclusive_monitor (
    .clk, .resetn,
    .reserveValid(requestHandshake && incomingReq.exclOrSnoopMeOrCah
                  && !isWrite(incomingReq.opcode)),
    .reserveReady(exclReserveReady), .reserveLineAddr(incomingLine),
    .reserveRequester(incomingReq.srcId),
    .exclusiveCheckValid(requestHandshake && incomingReq.exclOrSnoopMeOrCah
                         && isWrite(incomingReq.opcode)),
    .exclusiveLineAddr(incomingLine),
    .exclusiveRequester(incomingReq.srcId), .exclusiveOkay(exclOkay),
    .conflictValid((requestHandshake && isWrite(incomingReq.opcode))
                   || snpOutValid),
    .conflictIsWriteOrSnoop(1'b1),
    .conflictLineAddr(requestHandshake ? incomingLine : snpStartLine)
  );

  chi_dct_ctrl #(.CFG(CFG)) dct_ctrl (
    .requestOpcode(activeReq.opcode), .requestOrder(activeReq.order),
    .requester(activeReq.srcId), .requesterTxnId(activeReq.txnId),
    .forwarderKnown(sfHasOwner), .forwarder(RNF_NODE_IDS[sfOwner]),
    .forwarderClean(sfPrecise), .dataPresent(sfHit), .dataFullLine(sfPrecise),
    .dataPoison(1'b0), .dataError(1'b0), .responseCompatible(1'b1),
    .mteCompatible(!CFG.mteEn), .eligible(dctEligible),
    .fallbackToHome(dctFallback), .snoopOpcode(dctOpcode),
    .fwdNid(dctFwdNid), .fwdTxnId(dctFwdTxn), .retToSrc(dctRetToSrc)
  );

  chi_dmt_ctrl #(.CFG(CFG)) dmt_ctrl (
    .requestOpcode(incomingReq.opcode), .requestOrder(incomingReq.order),
    .requester(incomingReq.srcId), .requesterTxnId(incomingReq.txnId),
    .snoopRequired(sfHit && (sfSharers != '0)), .errorDetected(1'b0),
    .exclusiveAccess(incomingReq.exclOrSnoopMeOrCah),
    .atomicAccess(atomicRequest), .eligible(dmtEligible),
    .separateResponse(dmtSeparateResponse), .returnNid(dmtReturnNid),
    .returnTxnId(dmtReturnTxnId)
  );

  chi_dwt_ctrl #(.CFG(CFG)) dwt_ctrl (
    .requestOpcode(incomingReq.opcode), .requestOrder(incomingReq.order),
    .requester(incomingReq.srcId), .requesterTxnId(incomingReq.txnId),
    .snoopRequired(sfHit && (sfSharers != '0)), .errorDetected(1'b0),
    .exclusiveAccess(incomingReq.exclOrSnoopMeOrCah),
    .atomicAccess(atomicRequest),
    .tagOperation(incomingReq.tagOp != TAG_OP_INVALID),
    .eligible(dwtEligible), .doDwt(dwtDoDwt), .returnNid(dwtReturnNid),
    .returnTxnId(dwtReturnTxnId)
  );

  // ReadReceipt tells the Requester its request has been accepted and will
  // not be retried, which is what Order = Request accepted asks for
  // (IHI 0050H B2.7).
  always_comb begin
    orderedReceiptRequired = (incomingReq.order == ORDER_REQUEST_ACCEPTED)
                             && ((incomingReq.opcode == REQ_READ_NO_SNP)
                                 || (incomingReq.opcode == REQ_READ_NO_SNP_SEP)
                                 || (incomingReq.opcode == REQ_READ_ONCE));
    orderResponse = '0;
    orderResponse.qos = activeReq.qos;
    orderResponse.tgtId = activeReq.srcId;
    orderResponse.srcId = HN_NODE_ID;
    orderResponse.txnId = activeReq.txnId;
    orderResponse.opcode = (state == HNF_ORDER_RECEIPT)
                           ? RSP_READ_RECEIPT : RSP_RESP_SEP_DATA;
    orderResponse.resp = RESP_I;
    orderResponse.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(activePosIndex);
  end

  chi_stash_ctrl #(
    .CFG(CFG), .NUM_RNF(NUM_RNF), .RNF_NODE_IDS(RNF_NODE_IDS)
  ) stash_ctrl (
    .requestOpcode(incomingReq.opcode),
    .requestStashNidValid(incomingReq.stashNidValidOrEndianOrDeep),
    .requestStashNid(incomingReq.returnNidOrStashNidOrDataTarget),
    .requestStashLpidSlot(incomingReq.returnTxnIdOrStashLpid),
    .homeHasLatestCopy(sfHit && !sfHasOwner), .isStash(stashIsStash),
    .isIndependentStash(stashIndependent),
    .isSeparateStashDone(stashSeparateDone),
    .isUniqueStash(stashUnique),
    .targetValid(stashTargetValid), .targetMask(stashTargetMask),
    .targetSnoopOpcode(stashTargetSnoop), .stashLpidValid(stashLpidValid),
    .stashLpid(stashLpid), .dataPullOpcode(stashPullOpcode),
    .dataPullResp(stashPullResp)
  );

  // A stash target that answered with Data Pull is owed the cache line, so the
  // Home reads it and returns CompData under the TxnID the target supplied
  // (IHI 0050H B7.1.1).
  always_comb begin
    stashPullPending = activeStash && dataPullValid;

    stashResponse = '0;
    stashResponse.qos = activeReq.qos;
    stashResponse.tgtId = activeReq.srcId;
    stashResponse.srcId = HN_NODE_ID;
    stashResponse.txnId = activeReq.txnId;
    // Comp_I is the correct answer whenever the Home does not know that the
    // line is held in the next-level cache (IHI 0050H B7.3).
    stashResponse.resp = RESP_I;
    // StashDone reuses the DBID slot for the Requester's StashGroupID.
    stashResponse.dbIdOrGroupId =
      CHI_RSP_DBID_SLOT_W'(activeReq.groupIdOrLpid);
    if (state == HNF_STASH_DONE)
      stashResponse.opcode = RSP_STASH_DONE;
    else if (activeStashSeparate && COMBINED_COMP_STASH_DONE)
      stashResponse.opcode = RSP_COMP_STASH_DONE;
    else
      stashResponse.opcode = RSP_COMP;

    pullReq = '0;
    pullReq.qos = activeReq.qos;
    pullReq.tgtId = SN_NODE_ID;
    pullReq.srcId = HN_NODE_ID;
    pullReq.txnId = CHI_TXNID_FLIT_W'(activePosIndex);
    pullReq.addr = activeReq.addr;
    pullReq.pas = activeReq.pas;
    pullReq.memAttr = activeReq.memAttr;
    pullReq.size = 3'd6;
    pullReq.opcode = REQ_READ_NO_SNP;

    pullDat = incomingDat;
    pullDat.tgtId = dataPullTarget;
    pullDat.srcId = HN_NODE_ID;
    pullDat.txnId = CHI_MAX_TXNID_W'(dataPullTxnId);
    pullDat.homeNidOrPbha = HN_NODE_ID;
    pullDat.opcode = DAT_COMP_DATA;
    pullDat.resp = activeStashPullResp;
    pullDat.dbId = '0;
    pullDat.dataPull = 1'b0;
  end

  // PCrdGrant names the recorded Requester and carries no TxnID or DBID
  // (IHI 0050H B2.5.5).
  always_comb begin
    grantFlit = '0;
    grantFlit.tgtId = retryGrantTgtId;
    grantFlit.srcId = HN_NODE_ID;
    grantFlit.txnId = '0;
    grantFlit.dbIdOrGroupId = '0;
    grantFlit.opcode = RSP_PCRD_GRANT;
    grantFlit.pCrdType = retryGrantClass;
    grantFlit.resp = RESP_I;
  end

  always_comb begin
    atomicByteOffset = activeReq.addr[DAT_OFF_W-1:0];
    // AtomicCompare carries the compare value and the swap value together, so
    // its Size covers both and each operand is half of it (IHI 0050H B4.2.5).
    atomicOperandSize = (activeReq.opcode == REQ_ATOMIC_COMPARE)
                        ? (activeReq.size - 3'd1) : activeReq.size;
    // The compare value occupies the lower-addressed half of the outbound
    // data and the swap value the upper half. The specification names the two
    // values but does not state this placement in the text available here.
    if (activeReq.opcode == REQ_ATOMIC_COMPARE) begin
      atomicCompareData = extractWord(atomicOperandBuffer, atomicByteOffset);
      atomicTransactionData = extractWord(
        atomicOperandBuffer,
        atomicByteOffset + DAT_OFF_W'(1 << atomicOperandSize));
    end else begin
      atomicCompareData = '0;
      atomicTransactionData =
        extractWord(atomicOperandBuffer, atomicByteOffset);
    end
    atomicInitialWord = extractWord(atomicInitialBuffer, atomicByteOffset);
    atomicStateActive = (state == HNF_ATOMIC_DBID)
                        || (state == HNF_ATOMIC_OPERAND)
                        || (state == HNF_ATOMIC_READ)
                        || (state == HNF_ATOMIC_INITIAL)
                        || (state == HNF_ATOMIC_WRITE)
                        || (state == HNF_ATOMIC_WDATA)
                        || (state == HNF_ATOMIC_WCOMP)
                        || (state == HNF_ATOMIC_RETURN);
  end

  chi_atomic_alu atomic_alu (
    .opcode(activeReq.opcode), .size(atomicOperandSize),
    .bigEndian(activeReq.stashNidValidOrEndianOrDeep),
    .initialData(atomicInitialWord),
    .transactionData(atomicTransactionData),
    .compareData(atomicCompareData), .isAtomic(atomicOpcodeValid),
    .returnsData(atomicReturnsData), .updateEnable(atomicUpdateEnable),
    .updateData(atomicUpdateWord), .originalData(atomicOriginalWord)
  );

  // The Home Node is the Point of Coherency for a far atomic, so it reads the
  // line, applies the operation, and writes the result back downstream
  // (IHI 0050H B4.2.5). Atomics may not use DMT or DWT.
  always_comb begin
    atomicDownstreamReq = '0;
    atomicDownstreamReq.qos = activeReq.qos;
    atomicDownstreamReq.tgtId = SN_NODE_ID;
    atomicDownstreamReq.srcId = HN_NODE_ID;
    atomicDownstreamReq.txnId = activeReq.txnId;
    atomicDownstreamReq.addr = activeReq.addr;
    atomicDownstreamReq.pas = activeReq.pas;
    atomicDownstreamReq.memAttr = activeReq.memAttr;
    atomicDownstreamReq.size = 3'd6;
    atomicDownstreamReq.opcode = (state == HNF_ATOMIC_WRITE)
                                 ? REQ_WRITE_NO_SNP_PTL : REQ_READ_NO_SNP;

    atomicDownstreamDat = '0;
    atomicDownstreamDat.qos = activeReq.qos;
    atomicDownstreamDat.tgtId = SN_NODE_ID;
    atomicDownstreamDat.srcId = HN_NODE_ID;
    atomicDownstreamDat.txnId = activeReq.txnId;
    atomicDownstreamDat.homeNidOrPbha = HN_NODE_ID;
    atomicDownstreamDat.opcode = DAT_NON_COPY_BACK_WR_DATA;
    atomicDownstreamDat.resp = RESP_I;
    atomicDownstreamDat.data[CFG.dataW-1:0] =
      insertWord(atomicInitialBuffer, atomicByteOffset, atomicUpdateWord,
                 atomicOperandSize);
    atomicDownstreamDat.be[DAT_BYTES-1:0] =
      operandByteEnables(atomicByteOffset, atomicOperandSize);

    atomicReturnDat = '0;
    atomicReturnDat.qos = activeReq.qos;
    atomicReturnDat.tgtId = activeReq.srcId;
    atomicReturnDat.srcId = HN_NODE_ID;
    atomicReturnDat.txnId = activeReq.txnId;
    atomicReturnDat.homeNidOrPbha = HN_NODE_ID;
    atomicReturnDat.opcode = DAT_COMP_DATA;
    // Atomic return data must not be cached at the Requester.
    atomicReturnDat.resp = RESP_I;
    atomicReturnDat.dbId = CHI_DAT_DBID_SLOT_W'(activeReq.txnId);
    atomicReturnDat.be[DAT_BYTES-1:0] =
      operandByteEnables(atomicByteOffset, atomicOperandSize);
    atomicReturnDat.data[CFG.dataW-1:0] =
      insertWord('0, atomicByteOffset, atomicOriginalWord,
                 atomicOperandSize);

    atomicResponse = '0;
    atomicResponse.qos = activeReq.qos;
    atomicResponse.tgtId = activeReq.srcId;
    atomicResponse.srcId = HN_NODE_ID;
    atomicResponse.txnId = activeReq.txnId;
    atomicResponse.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(activeReq.txnId);
    atomicResponse.resp = RESP_I;
    atomicResponse.opcode = (state == HNF_ATOMIC_DBID) ? RSP_DBID_RESP
                                                       : RSP_COMP;
  end

  chi_pos #(.CFG(CFG), .DEPTH(POS_DEPTH)) pos (
    .clk, .resetn,
    .allocValid(requestHandshake && !droppedRequest),
    .allocReady(posAllocReady), .allocLineAddr(incomingLine),
    .allocRequester(incomingReq.srcId), .allocTxnId(incomingReq.txnId),
    .allocOpcode(incomingReq.opcode), .allocNeedSnoop(coherentRequest && sfHit),
    .allocNeedData(1'b1), .allocNeedComp(1'b1),
    .allocNeedCompAck(incomingReq.expCompAck), .allocIndex(posAllocIndex),
    .freeValid(posFree), .freeIndex(activePosIndex),
    .progressValid(posFree), .progressIndex(activePosIndex),
    .progressSnoopDone(posFree), .progressDataDone(posFree),
    .progressCompDone(posFree), .progressCompAckDone(posFree),
    .sameAddressBusy, .queryLineAddr(incomingLine), .active(posActive),
    .readyToFree(posReadyToFree), .lineAddr(posLine), .requester(posRequester),
    .txnId(posTxn), .opcode(posOpcode), .lifecycle(posLifecycle)
  );

  chi_snoop_filter #(
    .CFG(CFG), .ENTRIES((CFG.snpFilterEntries > 0) ? CFG.snpFilterEntries : 1),
    .WAYS((CFG.snpFilterWays > 0) ? CFG.snpFilterWays : 1), .NUM_RNF(NUM_RNF)
  ) snoop_filter (
    .clk, .resetn, .lookupValid(1'b1), .lookupLineAddr(
      (state == HNF_IDLE) ? incomingLine : activeReq.addr[CFG.addrW-1:6]),
    .lookupHit(sfHit), .lookupSharers(sfSharers), .lookupPrecise(sfPrecise),
    .lookupHasOwner(sfHasOwner), .lookupOwner(sfOwner),
    .updateValid(sfUpdate), .updateReady(sfUpdateReady),
    .updateLineAddr(activeReq.addr[CFG.addrW-1:6]),
    .updateSharers(sfUpdateSharers), .updatePrecise(1'b1),
    .updateHasOwner(sfUpdateHasOwner), .updateOwner(sfUpdateOwner),
    .invalidate(sfInvalidate),
    .backInvValid(sfBackInvValid), .backInvReady(sfBackInvReady),
    .backInvLineAddr(sfBackInvLine), .backInvSharers(sfBackInvSharers),
    .backInvDone(sfBackInvDone)
  );

  // A Data Pull hands the stash target a copy of the line, so the directory
  // records that target rather than the stash Requester.
  always_comb begin
    sfUpdateOwner = stashDirUpdate ? requesterIndex(dataPullTarget)
                                   : requesterIndex(activeReq.srcId);
    sfUpdateHasOwner = !sfInvalidate
                       && (stashDirUpdate ? activeStashUnique
                           : ((activeReq.opcode == REQ_READ_UNIQUE)
                              || (activeReq.opcode == REQ_MAKE_UNIQUE)));
  end

  always_comb begin
    snpStart = (state == HNF_SNOOP_START) || (state == HNF_BACKINV_START);
    // An independent stash request only hints the target; a write with stash
    // hint invalidates the peers as well (IHI 0050H B7.2, B7.3). The target is
    // snooped whether or not the directory records it as a sharer.
    snpStartSharers = (state == HNF_BACKINV_START) ? sfBackInvSharers
                      : (activeStashIndependent ? activeStashTargetMask
                         : (sfSharers | activeStashTargetMask));
    snpStartLine = (state == HNF_BACKINV_START)
                   ? sfBackInvLine : activeReq.addr[CFG.addrW-1:6];
    // An atomic must leave every peer copy Invalid, and CleanInvalid also
    // recovers a dirty copy for the read-modify-write.
    snpStartOpcode = (state == HNF_BACKINV_START) ? SNP_MAKE_INVALID :
                     (activeAtomic ? SNP_CLEAN_INVALID :
                      (dctEligible ? dctOpcode :
                       (activeWrite ? SNP_UNIQUE : SNP_SHARED)));
    snpStartTxn = (state == HNF_BACKINV_START) ? '0 : activeReq.txnId;
    snpFwdNid = dctEligible ? dctFwdNid : '0;
    snpFwdTxn = dctEligible ? dctFwdTxn : '0;
    snpRetToSrc = (dctEligible && !activeAtomic) ? dctRetToSrc : 1'b1;
    sfBackInvReady = state == HNF_BACKINV_START && snpStartReady;
    sfBackInvDone = state == HNF_BACKINV_WAIT && snpDone;
  end

  chi_snp_gen #(
    .CFG(CFG), .NUM_RNF(NUM_RNF), .RNF_NODE_IDS(RNF_NODE_IDS),
    .HN_NODE_ID(HN_NODE_ID)
  ) snoop_generator (
    .clk, .resetn, .startValid(snpStart), .startReady(snpStartReady),
    .startSharers(snpStartSharers), .startLineAddr(snpStartLine),
    .startOpcode(snpStartOpcode), .startTxnId(snpStartTxn),
    .startFwdNid(snpFwdNid), .startFwdTxnId(snpFwdTxn),
    .startRetToSrc(snpRetToSrc), .startPas(activeReq.pas),
    .startStashTarget(activeStashTargetMask),
    .startStashOpcode(activeStashSnoop),
    .startStashLpidValid(activeStashLpidValid),
    .startStashLpid(activeStashLpid),
    .snpValid(snpOutValid), .snpReady(snpOutReady), .snpFlit(snpOutFlit),
    .responseValid(rspInValid
      && ((incomingRsp.opcode == RSP_SNP_RESP)
          || (incomingRsp.opcode == RSP_SNP_RESP_FWDED))),
    .responseReady(snpRspReady), .responseSource(incomingRsp.srcId),
    // DataPull occupies the low bit of the shared FwdState slot and the TxnID
    // for the implied read arrives in DBID (IHI 0050H Table B13.7).
    .responseDataPull(incomingRsp.fwdState[0]),
    .responseDbId(incomingRsp.dbIdOrGroupId),
    .dataPullValid(dataPullValid), .dataPullTarget(dataPullTarget),
    .dataPullTxnId(dataPullTxnId), .busy(snpBusy), .done(snpDone)
  );

  // The Home Node partitions its P-Credits by request category so that a
  // stalled write cannot hold back a read (IHI 0050H B2.10).
  always_comb begin
    if (atomicRequest)
      retryCategory = 2'd3;
    else if (isWrite(incomingReq.opcode))
      retryCategory = 2'd1;
    else if (isCoherent(incomingReq.opcode))
      retryCategory = 2'd2;
    else
      retryCategory = 2'd0;
  end

  chi_retry #(
    .NODEID_W(chi_cfg_pkg::CHI_NODEID_SLOT_W), .ENTRIES(RETRY_RECORDS),
    .CREDIT_TYPES(CHI_CREDIT_TYPES)
  ) retry (
    .clk, .resetn, .requestValid(reqInValid),
    .resourcesAvailable, .allowRetry(incomingReq.allowRetry),
    .requestCategory(retryCategory), .requestSrcId(incomingReq.srcId),
    .requestQos(incomingReq.qos), .acceptRequest(retryAccept),
    .sendRetryAck(retryAck), .retryAckSent(retryHandshake),
    .retryClass, .recordFull(retryRecordFull),
    .creditUseValid(requestHandshake && !incomingReq.allowRetry
                    && !droppedRequest),
    .creditUseClass(incomingReq.pCrdType),
    .creditReturnValid(reqInValid && reqInReady
                       && (incomingReq.opcode == REQ_PCRD_RETURN)),
    .creditReturnClass(incomingReq.pCrdType),
    // Only one credit is outstanding at a time, so the resource the grant
    // promises is still free when the credited request arrives.
    .grantAllowed((state == HNF_IDLE) && posAllocReady && !sfBackInvValid
                  && !retryCreditsPending),
    .grantValid(retryGrantValid), .grantReady(retryGrantReady),
    .grantTgtId(retryGrantTgtId), .grantClass(retryGrantClass),
    .pendingCount(retryPending), .creditsOutstanding(retryOutstanding),
    .creditsPending(retryCreditsPending)
  );

  always_ff @(posedge clk) begin
    if (!resetn) begin
      state <= HNF_IDLE;
      activeReq <= '0;
      activePosIndex <= '0;
      activeCoherent <= 1'b0;
      activeWrite <= 1'b0;
      activeNeedsSnoop <= 1'b0;
      activeExclOkay <= 1'b0;
      activeNeedPersist <= 1'b0;
      activeGotComp <= 1'b0;
      activeGotPersist <= 1'b0;
      activeAtomic <= 1'b0;
      activeStash <= 1'b0;
      activeStashUnique <= 1'b0;
      activeStashIndependent <= 1'b0;
      activeStashSeparate <= 1'b0;
      activeStashTargetMask <= '0;
      activeStashSnoop <= SNP_STASH_SHARED;
      activeStashLpidValid <= 1'b0;
      activeStashLpid <= '0;
      activeStashPullResp <= RESP_I;
      activeDmt <= 1'b0;
      activeDmtSeparate <= 1'b0;
      activeDwt <= 1'b0;
      atomicOperandBuffer <= '0;
      atomicInitialBuffer <= '0;
      atomicInitialFromSnoop <= 1'b0;
      atomicDbidSeen <= 1'b0;
      atomicCompSeen <= 1'b0;
      atomicDataSent <= 1'b0;
      posFree <= 1'b0;
      sfUpdate <= 1'b0;
      sfUpdateSharers <= '0;
      sfInvalidate <= 1'b0;
      stashDirUpdate <= 1'b0;
    end else begin
      posFree <= 1'b0;
      sfUpdate <= 1'b0;
      stashDirUpdate <= 1'b0;
      case (state)
        HNF_IDLE: begin
          if (sfBackInvValid)
            state <= HNF_BACKINV_START;
          else if (requestHandshake && !droppedRequest) begin
            activeReq <= incomingReq;
            activePosIndex <= posAllocIndex;
            activeCoherent <= coherentRequest;
            activeAtomic <= atomicRequest;
            activeStash <= stashIsStash;
            activeStashUnique <= stashUnique;
            activeStashIndependent <= stashIndependent;
            activeStashSeparate <= stashSeparateDone;
            activeStashTargetMask <= stashTargetValid ? stashTargetMask : '0;
            activeStashSnoop <= stashTargetSnoop;
            activeStashLpidValid <= stashLpidValid;
            activeStashLpid <= stashLpid;
            activeStashPullResp <= stashPullResp;
            activeDmt <= dmtEligible;
            activeDmtSeparate <= dmtEligible && dmtSeparateResponse;
            activeDwt <= dwtEligible && dwtDoDwt;
            atomicInitialFromSnoop <= 1'b0;
            atomicDbidSeen <= 1'b0;
            atomicCompSeen <= 1'b0;
            atomicDataSent <= 1'b0;
            atomicInitialBuffer <= '0;
            activeWrite <= isWrite(incomingReq.opcode) || cmoWrite;
            activeNeedsSnoop <= stashTargetValid
                                || ((coherentRequest || activeCmo) && sfHit
                                    && (sfSharers != '0));
            activeExclOkay <= !incomingReq.exclOrSnoopMeOrCah
                              || (isWrite(incomingReq.opcode)
                                  ? exclOkay : exclReserveReady);
            activeNeedPersist <= cmoPersist;
            activeGotComp <= 1'b0;
            activeGotPersist <= !cmoPersist;
            if (orderedReceiptRequired)
              state <= HNF_ORDER_RECEIPT;
            else if (stashTargetValid
                     || (((coherentRequest || activeCmo || atomicRequest)
                          && sfHit && (sfSharers != '0))))
              state <= HNF_SNOOP_START;
            else if (atomicRequest)
              state <= HNF_ATOMIC_DBID;
            // A stash request without a target has no data to move, so the
            // Home completes it immediately (IHI 0050H B7.4.2).
            else if (stashIndependent)
              state <= HNF_STASH_COMP;
            else
              state <= HNF_REQ_SEND;
          end
        end
        HNF_SNOOP_START:
          if (snpStart && snpStartReady)
            state <= HNF_SNOOP_WAIT;
        HNF_SNOOP_WAIT: begin
          if (activeAtomic && datInValid
              && ((incomingDat.opcode == DAT_SNP_RESP_DATA)
                  || (incomingDat.opcode == DAT_SNP_RESP_DATA_PTL))) begin
            atomicInitialBuffer <= incomingDat.data[CFG.dataW-1:0];
            atomicInitialFromSnoop <= 1'b1;
          end
          if (snpDone)
            state <= activeAtomic ? HNF_ATOMIC_DBID
                     : (activeStashIndependent ? HNF_STASH_COMP
                        : HNF_REQ_SEND);
        end
        HNF_STASH_COMP:
          if (rspOutValid && rspOutReady) begin
            if (activeStashSeparate && !COMBINED_COMP_STASH_DONE)
              state <= HNF_STASH_DONE;
            else if (stashPullPending)
              state <= HNF_PULL_REQ;
            else begin
              state <= HNF_IDLE;
              posFree <= 1'b1;
            end
          end
        HNF_STASH_DONE:
          if (rspOutValid && rspOutReady) begin
            if (stashPullPending)
              state <= HNF_PULL_REQ;
            else begin
              state <= HNF_IDLE;
              posFree <= 1'b1;
            end
          end
        HNF_PULL_REQ:
          if (reqOutValid && reqOutReady)
            state <= HNF_PULL_DATA;
        HNF_PULL_DATA:
          if (datOutValid && datOutReady
              && (incomingDat.dataId == incomingDat.numDat)) begin
            state <= HNF_IDLE;
            posFree <= 1'b1;
            sfUpdate <= 1'b1;
            sfInvalidate <= 1'b0;
            stashDirUpdate <= 1'b1;
            sfUpdateSharers <= activeStashUnique
                               ? requesterBit(dataPullTarget)
                               : (sfSharers | requesterBit(dataPullTarget));
          end
        HNF_ATOMIC_DBID:
          if (rspOutValid && rspOutReady)
            state <= HNF_ATOMIC_OPERAND;
        HNF_ATOMIC_OPERAND:
          if (datInValid && datInReady) begin
            atomicOperandBuffer <= incomingDat.data[CFG.dataW-1:0];
            state <= atomicInitialFromSnoop ? HNF_ATOMIC_WRITE
                                            : HNF_ATOMIC_READ;
          end
        HNF_ATOMIC_READ:
          if (reqOutValid && reqOutReady)
            state <= HNF_ATOMIC_INITIAL;
        HNF_ATOMIC_INITIAL:
          if (datInValid && datInReady
              && (incomingDat.opcode == DAT_COMP_DATA)) begin
            atomicInitialBuffer <= incomingDat.data[CFG.dataW-1:0];
            state <= HNF_ATOMIC_WRITE;
          end
        HNF_ATOMIC_WRITE: begin
          if (!atomicUpdateEnable)
            state <= HNF_ATOMIC_RETURN;
          else if (reqOutValid && reqOutReady)
            state <= HNF_ATOMIC_WCOMP;
        end
        HNF_ATOMIC_WCOMP: begin
          if (rspInValid && rspInReady) begin
            if ((incomingRsp.opcode == RSP_DBID_RESP)
                || (incomingRsp.opcode == RSP_DBID_RESP_ORD)
                || (incomingRsp.opcode == RSP_COMP_DBID_RESP))
              atomicDbidSeen <= 1'b1;
            if ((incomingRsp.opcode == RSP_COMP)
                || (incomingRsp.opcode == RSP_COMP_DBID_RESP))
              atomicCompSeen <= 1'b1;
          end
          if (!atomicDataSent && atomicDbidSeen)
            state <= HNF_ATOMIC_WDATA;
          else if (atomicDataSent && atomicCompSeen)
            state <= HNF_ATOMIC_RETURN;
        end
        HNF_ATOMIC_WDATA:
          if (datOutValid && datOutReady) begin
            atomicDataSent <= 1'b1;
            state <= HNF_ATOMIC_WCOMP;
          end
        HNF_ATOMIC_RETURN: begin
          if ((atomicReturnsData && datOutValid && datOutReady)
              || (!atomicReturnsData && rspOutValid && rspOutReady)) begin
            posFree <= 1'b1;
            activeAtomic <= 1'b0;
            state <= activeReq.expCompAck ? HNF_WAIT_COMP_ACK : HNF_IDLE;
          end
        end
        HNF_ORDER_RECEIPT:
          if (rspOutValid && rspOutReady) begin
            if (activeAtomic)
              state <= HNF_ATOMIC_DBID;
            else if (activeNeedsSnoop)
              state <= HNF_SNOOP_START;
            else
              state <= HNF_REQ_SEND;
          end
        HNF_REQ_SEND:
          if (reqOutValid && reqOutReady) begin
            // With DMT the read data goes straight from the Subordinate to
            // the Requester, so the Home leaves the data path entirely.
            if (activeDmt && activeDmtSeparate)
              state <= HNF_DMT_RESP;
            else if (activeDmt) begin
              if (activeReq.expCompAck)
                state <= HNF_WAIT_COMP_ACK;
              else begin
                state <= HNF_IDLE;
                posFree <= 1'b1;
              end
            end else
              state <= HNF_WAIT_RESPONSE;
          end
        HNF_DMT_RESP:
          if (rspOutValid && rspOutReady) begin
            if (activeReq.expCompAck)
              state <= HNF_WAIT_COMP_ACK;
            else begin
              state <= HNF_IDLE;
              posFree <= 1'b1;
            end
          end
        HNF_WAIT_RESPONSE: begin
          if (rspInValid && rspInReady) begin
            if ((incomingRsp.opcode == RSP_COMP)
                || (incomingRsp.opcode == RSP_COMP_DBID_RESP)
                || (incomingRsp.opcode == RSP_COMP_CMO)
                || (incomingRsp.opcode == RSP_COMP_PERSIST))
              activeGotComp <= 1'b1;
            if ((incomingRsp.opcode == RSP_PERSIST)
                || (incomingRsp.opcode == RSP_COMP_PERSIST))
              activeGotPersist <= 1'b1;
            if ((activeGotComp || (incomingRsp.opcode == RSP_COMP)
                 || (incomingRsp.opcode == RSP_COMP_DBID_RESP)
                 || (incomingRsp.opcode == RSP_COMP_CMO)
                 || (incomingRsp.opcode == RSP_COMP_PERSIST))
                && (activeGotPersist || !activeNeedPersist
                    || (incomingRsp.opcode == RSP_PERSIST)
                    || (incomingRsp.opcode == RSP_COMP_PERSIST))) begin
              if (activeReq.expCompAck)
                state <= HNF_WAIT_COMP_ACK;
              else begin
                // A write with stash hint whose target asked for Data Pull
                // still owes that target the cache line.
                state <= stashPullPending ? HNF_PULL_REQ : HNF_IDLE;
                posFree <= !stashPullPending;
                if (activeCoherent) begin
                  sfUpdate <= 1'b1;
                  if (activeWrite)
                    sfUpdateSharers <= '0;
                  else if ((activeReq.opcode == REQ_READ_UNIQUE)
                           || (activeReq.opcode == REQ_MAKE_UNIQUE))
                    sfUpdateSharers <= requesterBit(activeReq.srcId);
                  else
                    sfUpdateSharers <= sfSharers
                                       | requesterBit(activeReq.srcId);
                  sfInvalidate <= activeWrite;
                end
              end
            end
          end else if (datInValid && datInReady
                       && (incomingDat.opcode == DAT_COMP_DATA)
                       && (incomingDat.dataId == incomingDat.numDat)) begin
            if (activeReq.expCompAck) begin
              state <= HNF_WAIT_COMP_ACK;
            end else begin
              state <= stashPullPending ? HNF_PULL_REQ : HNF_IDLE;
              posFree <= !stashPullPending;
            end
            if (activeCoherent) begin
              sfUpdate <= 1'b1;
              if (activeWrite)
                sfUpdateSharers <= '0;
              else if ((activeReq.opcode == REQ_READ_UNIQUE)
                       || (activeReq.opcode == REQ_MAKE_UNIQUE))
                sfUpdateSharers <= requesterBit(activeReq.srcId);
              else
                sfUpdateSharers <= sfSharers
                                   | requesterBit(activeReq.srcId);
              sfInvalidate <= activeWrite;
            end
          end
        end
        HNF_WAIT_COMP_ACK: begin
          if (rspInValid && (incomingRsp.opcode == RSP_COMP_ACK)
              && (incomingRsp.srcId == activeReq.srcId)) begin
            state <= stashPullPending ? HNF_PULL_REQ : HNF_IDLE;
            posFree <= !stashPullPending;
          end
        end
        HNF_BACKINV_START:
          if (snpStart && snpStartReady)
            state <= HNF_BACKINV_WAIT;
        HNF_BACKINV_WAIT:
          if (snpDone)
            state <= HNF_IDLE;
        default: state <= HNF_IDLE;
      endcase
    end
  end
endmodule
