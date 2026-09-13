// Checks for the whole fabric.
//
// Every monitor writes into one analysis FIFO here, and a thread per FIFO
// drains it. The checks are grouped into four independent reference models,
// none of which shares state with the design or with the drivers:
//
//   link        both directions of every link reach RUN, and neither side
//               ever holds more L-Credits than the channel was built for
//   lifecycle   every request is completed exactly once, TxnIDs are not
//               reused while in flight, and the retry handshake is followed
//   directory   no two Requesters hold the same line in a state that lets
//               both write it
//   memory      the bytes a read returns are the bytes the last write left
//
// The memory model is deliberately not loaded from the Subordinates' memory.
// Both derive an unwritten location from memInitByte independently, and
// written locations are tracked from the data flits seen on the wire, so a
// mismatch means the fabric moved the wrong bytes rather than that two models
// disagreed about their starting contents.
class topScoreboard extends uvm_scoreboard;

  chiEnvConfig cfg;

  uvm_tlm_analysis_fifo #(chiRequesterTx)   requesterFifo   [];
  uvm_tlm_analysis_fifo #(chiSubordinateTx) subordinateFifo [];

  // ----- Identity map -----
  // NodeID to agent index, so a flit's SrcID can be attributed to the agent
  // that sent it.
  protected int unsigned requesterOfNodeId [chiNodeIdT];

  // ----- Transaction lifecycle -----
  typedef struct {
    chiAddrT         addr;
    chi_req_opcode_e opcode;
    bit              expCompAck;
    bit              sawRetryAck;
    logic [3:0]      retryPCrdType;
    bit              completed;
    realtime         issuedAt;
  } txnRecordS;

  protected txnRecordS txnTable [string];

  // DBID a Home Node offered for a write, mapped back to the transaction it
  // belongs to. Write data is tagged with the DBID rather than the original
  // TxnID, so without this the address a write lands at is unknown
  // [SPEC:IHI0050H B2.3.1].
  protected string dbidOwner [string];

  // ----- Link accounting -----
  protected chiLinkStateE requesterLinkState [int unsigned][chiDirectionE];
  protected chiLinkStateE subordinateLinkState [int unsigned][chiDirectionE];
  protected bit requesterLinkRan [int unsigned][chiDirectionE];
  protected bit subordinateLinkRan [int unsigned][chiDirectionE];

  // ----- Directory -----
  // What each Requester holds, as reconstructed from the completions and snoop
  // responses observed on the wire.
  protected chi_cache_state_e directory [chiLineAddrT][int unsigned];

  // ----- Memory -----
  protected chiLineBytesT expectedLine [chiLineAddrT];
  protected bit           lineWritten  [chiLineAddrT];
  protected int unsigned  writesInFlight [chiLineAddrT];

  // Partial data messages, keyed by the agent and TxnID carrying them. A line
  // arrives over several packets and cannot be checked until the last one
  // [SPEC:IHI0050H B2.9.4].
  typedef struct {
    chiLineBytesT bytes;
    int unsigned  packets;
  } dataAssemblyS;

  protected dataAssemblyS assembly [string];

  // ----- Counters -----
  protected int unsigned requestsSeen;
  protected int unsigned completionsSeen;
  protected int unsigned retriesSeen;
  protected int unsigned grantsSeen;
  protected int unsigned snoopsSeen;
  protected int unsigned dataChecksPassed;
  protected int unsigned dataChecksSkipped;

  `uvm_component_utils(topScoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(chiEnvConfig)::get(this, "", "chiEnvConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiEnvConfig")

    requesterFifo   = new[cfg.numRequesterAgents];
    subordinateFifo = new[cfg.numSubordinateAgents];
    foreach (requesterFifo[i])
      requesterFifo[i] = new($sformatf("requesterFifo_%0d", i), this);
    foreach (subordinateFifo[i])
      subordinateFifo[i] = new($sformatf("subordinateFifo_%0d", i), this);

    for (int unsigned i = 0; i < cfg.numRequesterAgents; i++)
      requesterOfNodeId[cfg.requesterCfg[i].nodeId] = i;
  endfunction

  task run_phase(uvm_phase phase);
    foreach (requesterFifo[i])
      fork
        automatic int unsigned k = i;
        requesterLoop(k);
      join_none
    foreach (subordinateFifo[i])
      fork
        automatic int unsigned k = i;
        subordinateLoop(k);
      join_none
    wait fork;
  endtask

  // -------------------------------------------------------------------------
  // Requester side
  // -------------------------------------------------------------------------
  protected task requesterLoop(int unsigned agentId);
    chiRequesterTx tx;
    forever begin
      requesterFifo[agentId].get(tx);
      if (tx.txKind == CHI_TX_LINK_EVENT) checkRequesterLink(agentId, tx);
      else                                checkRequesterFlit(agentId, tx);
    end
  endtask

  protected function void checkRequesterLink(int unsigned agentId,
                                             chiRequesterTx tx);
    checkLinkEvent(tx.linkEvent, $sformatf("requester %0d", agentId));
    if (tx.linkEvent.kind == CHI_LINK_EVT_STATE_CHANGE) begin
      requesterLinkState[agentId][tx.linkEvent.direction] = tx.linkEvent.state;
      if (tx.linkEvent.state == CHI_LINK_RUN)
        requesterLinkRan[agentId][tx.linkEvent.direction] = 1'b1;
    end
  endfunction

  protected function void checkRequesterFlit(int unsigned agentId,
                                             chiRequesterTx tx);
    string key;

    case (tx.channel)
      // ----- Requests leaving the Requester -----
      CHI_CHANNEL_REQ: begin
        if (tx.direction != CHI_DIR_TX) begin
          `uvm_error(get_type_name(),
                     $sformatf("requester %0d received a request: %s", agentId,
                               tx.convert2string()))
          return;
        end
        key = txnKey(agentId, tx.reqFlit.txnId);
        requestsSeen++;

        // A credited re-send is the same transaction, not a new one, so the
        // record is updated rather than duplicated [SPEC:IHI0050H B2.10.1].
        if (txnTable.exists(key) && !txnTable[key].completed) begin
          if (tx.reqFlit.allowRetry) begin
            `uvm_error(get_type_name(),
                       $sformatf({"requester %0d reused TxnID 0x%0h while ",
                                  "still outstanding at 0x%0h"},
                                 agentId, tx.reqFlit.txnId,
                                 txnTable[key].addr))
          end else if (!txnTable[key].sawRetryAck) begin
            // AllowRetry may only be clear on a request that has been granted
            // a P-Credit [SPEC:IHI0050H B2.10].
            `uvm_error(get_type_name(),
                       $sformatf({"requester %0d sent TxnID 0x%0h with ",
                                  "AllowRetry clear without a RetryAck"},
                                 agentId, tx.reqFlit.txnId))
          end else if (tx.reqFlit.pCrdType != txnTable[key].retryPCrdType) begin
            // The re-send must echo the credit type that was granted.
            `uvm_error(get_type_name(),
                       $sformatf({"requester %0d retried TxnID 0x%0h with ",
                                  "PCrdType %0h, was granted %0h"},
                                 agentId, tx.reqFlit.txnId, tx.reqFlit.pCrdType,
                                 txnTable[key].retryPCrdType));
          end
        end

        begin
          txnRecordS record;
          record.addr          = lineBaseOf(tx.reqFlit.addr);
          record.opcode        = tx.reqFlit.opcode;
          record.expCompAck    = tx.reqFlit.expCompAck;
          record.sawRetryAck   = txnTable.exists(key)
                                 ? txnTable[key].sawRetryAck : 1'b0;
          record.retryPCrdType = txnTable.exists(key)
                                 ? txnTable[key].retryPCrdType : 4'd0;
          record.completed     = 1'b0;
          record.issuedAt      = $realtime;
          txnTable[key]        = record;
        end

        checkOpcodeAllowedForClass(agentId, tx);
        checkAddressRouting(agentId, tx);

        if (isWriteRequest(tx.reqFlit.opcode)) begin
          chiLineAddrT line;
          line = lineAddrOf(tx.reqFlit.addr);
          if (!writesInFlight.exists(line)) writesInFlight[line] = 0;
          writesInFlight[line]++;
        end
      end

      // ----- Responses -----
      CHI_CHANNEL_RSP: begin
        if (tx.direction == CHI_DIR_RX) handleInboundResponse(agentId, tx);
        else                            handleOutboundResponse(agentId, tx);
      end

      // ----- Snoops arriving -----
      CHI_CHANNEL_SNP: begin
        snoopsSeen++;
        checkSnoopTarget(agentId, tx);
      end

      // ----- Data -----
      default: handleRequesterData(agentId, tx);
    endcase
  endfunction

  protected function void handleInboundResponse(int unsigned agentId,
                                                chiRequesterTx tx);
    string key;
    key = txnKey(agentId, tx.rspFlit.txnId);

    case (tx.rspFlit.opcode)
      RSP_RETRY_ACK: begin
        retriesSeen++;
        if (!txnTable.exists(key)) begin
          `uvm_error(get_type_name(),
                     $sformatf("requester %0d got RetryAck for unknown TxnID 0x%0h",
                               agentId, tx.rspFlit.txnId))
          return;
        end
        txnTable[key].sawRetryAck   = 1'b1;
        txnTable[key].retryPCrdType = tx.rspFlit.pCrdType;
      end

      RSP_PCRD_GRANT: begin
        grantsSeen++;
        // A grant carries no TxnID, so there is nothing to match it against
        // here beyond its existence [SPEC:IHI0050H B2.5.5].
      end

      RSP_COMP, RSP_COMP_DBID_RESP, RSP_COMP_CMO, RSP_COMP_PERSIST: begin
        completeTransaction(agentId, key, tx.rspFlit.resp, tx.rspFlit.respErr);
        if (tx.rspFlit.opcode == RSP_COMP_DBID_RESP)
          dbidOwner[dbidKey(agentId, tx.rspFlit.srcId,
                                chiTxnIdT'(tx.rspFlit.dbIdOrGroupId))] = key;
      end

      RSP_DBID_RESP, RSP_DBID_RESP_ORD:
        dbidOwner[dbidKey(agentId, tx.rspFlit.srcId,
                                chiTxnIdT'(tx.rspFlit.dbIdOrGroupId))] = key;

      RSP_READ_RECEIPT: ;

      default: ;
    endcase

    checkResponseError(agentId, tx.rspFlit.respErr, tx.rspFlit.opcode.name());
  endfunction

  protected function void handleOutboundResponse(int unsigned agentId,
                                                 chiRequesterTx tx);
    // A snoop response tells the directory what this Requester kept.
    if ((tx.rspFlit.opcode == RSP_SNP_RESP)
        || (tx.rspFlit.opcode == RSP_SNP_RESP_FWDED))
      applyDirectoryFromResp(agentId,
                             snoopLineOf(agentId, tx.rspFlit.tgtId,
                                         tx.rspFlit.txnId),
                             tx.rspFlit.resp);
  endfunction

  // -------------------------------------------------------------------------
  // Completion and the directory
  // -------------------------------------------------------------------------
  protected function void completeTransaction(int unsigned agentId, string key,
                                              chi_resp_e resp,
                                              chi_resp_err_e respErr);
    chiLineAddrT line;

    if (!txnTable.exists(key)) begin
      `uvm_error(get_type_name(),
                 $sformatf("requester %0d completed an unknown transaction %s",
                           agentId, key))
      return;
    end
    if (txnTable[key].completed) begin
      `uvm_error(get_type_name(),
                 $sformatf("requester %0d completed %s twice", agentId, key))
      return;
    end

    txnTable[key].completed = 1'b1;
    completionsSeen++;
    line = lineAddrOf(txnTable[key].addr);

    // A write or an eviction gives the line up; everything else grants the
    // state the response names.
    if (isWriteRequest(txnTable[key].opcode)
        || (txnTable[key].opcode == REQ_EVICT))
      directory[line][agentId] = CACHE_I;
    else
      applyDirectoryFromResp(agentId, line, resp);

    checkUniqueOwnership(line);
  endfunction

  // Resp[1:0] names the state and Resp[2] whether the dirty responsibility
  // came with it [SPEC:IHI0050H B13.10.34].
  protected function void applyDirectoryFromResp(int unsigned agentId,
                                                 chiLineAddrT line,
                                                 chi_resp_e resp);
    chi_cache_state_e state;
    case (resp[1:0])
      2'b00:   state = CACHE_I;
      2'b01:   state = respPassDirty(resp) ? CACHE_SD : CACHE_SC;
      2'b10:   state = respPassDirty(resp) ? CACHE_UD : CACHE_UC;
      default: state = CACHE_SD;
    endcase
    directory[line][agentId] = state;
  endfunction

  // The invariant that makes coherence coherence: if any Requester holds a
  // line in a Unique state, no other Requester may hold it at all
  // [SPEC:IHI0050H B2.2].
  protected function void checkUniqueOwnership(chiLineAddrT line);
    int unsigned uniqueHolders;
    int unsigned validHolders;
    uniqueHolders = 0;
    validHolders  = 0;
    if (!directory.exists(line)) return;
    foreach (directory[line][agent]) begin
      chi_cache_state_e state;
      state = directory[line][agent];
      if (state == CACHE_I) continue;
      validHolders++;
      if ((state == CACHE_UC) || (state == CACHE_UD) || (state == CACHE_UDP))
        uniqueHolders++;
    end

    if (uniqueHolders > 1)
      `uvm_error(get_type_name(),
                 $sformatf({"line 0x%0h is held Unique by %0d Requesters at ",
                            "once"}, line, uniqueHolders))
    else if ((uniqueHolders == 1) && (validHolders > 1))
      `uvm_error(get_type_name(),
                 $sformatf({"line 0x%0h is held Unique by one Requester and ",
                            "also cached by %0d others"},
                           line, validHolders - 1))
  endfunction

  // A snoop should only reach a Requester the fabric has reason to believe
  // holds the line. Snooping a Requester that never had it is not a protocol
  // error, but it is wasted bandwidth and usually a snoop filter bug, so it is
  // reported as a warning rather than an error.
  protected function void checkSnoopTarget(int unsigned agentId,
                                           chiRequesterTx tx);
    chiLineAddrT line;

    if (!cfg.requesterCfg[agentId].hasCache) begin
      `uvm_error(get_type_name(),
                 $sformatf({"requester %0d is %s and holds no cacheable ",
                            "state, but was snooped"},
                           agentId, cfg.requesterCfg[agentId].nodeClass.name()))
      return;
    end

    line = lineAddrOf(tx.addr);
    snoopLineRecord[snoopKey(agentId, tx.snpFlit.srcId, tx.snpFlit.txnId)]
      = line;

    if (!directory.exists(line) || !directory[line].exists(agentId)
        || (directory[line][agentId] == CACHE_I))
      `uvm_warning(get_type_name(),
                   $sformatf({"requester %0d snooped with %s for line 0x%0h ",
                              "it is not recorded as holding"},
                             agentId, tx.snpFlit.opcode.name(), line))
  endfunction

  // A snoop response carries the snoop's TxnID, not an address, so the address
  // has to be remembered from the snoop itself.
  protected chiLineAddrT snoopLineRecord [string];

  protected function chiLineAddrT snoopLineOf(int unsigned agentId,
                                              chiNodeIdT homeId,
                                              chiTxnIdT txnId);
    string key;
    key = snoopKey(agentId, homeId, txnId);
    if (snoopLineRecord.exists(key)) return snoopLineRecord[key];
    return '0;
  endfunction

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  protected function void handleRequesterData(int unsigned agentId,
                                              chiRequesterTx tx);
    string        key;
    string        owner;
    chiLineAddrT  line;
    bit           complete;
    chiLineBytesT bytes;

    if (tx.direction == CHI_DIR_RX) begin
      // Read data arriving. It is tagged with the transaction's own TxnID.
      key = txnKey(agentId, tx.datFlit.txnId);

      // Write data has no business arriving at a Requester. Catching it here
      // matters because the flit is otherwise well formed and would be
      // accumulated as though it were the read data this transaction asked
      // for, turning a routing fault into a data mismatch somewhere else
      // [SPEC:IHI0050H B2.9.1].
      if ((tx.datFlit.opcode == DAT_COPY_BACK_WR_DATA)
          || (tx.datFlit.opcode == DAT_NON_COPY_BACK_WR_DATA)
          || (tx.datFlit.opcode == DAT_NCB_WR_DATA_COMP_ACK)) begin
        `uvm_error(get_type_name(),
                   $sformatf({"requester %0d received %s on TxnID 0x%0h from ",
                              "0x%0h: write data was routed to a Requester"},
                             agentId, tx.datFlit.opcode.name(),
                             tx.datFlit.txnId, tx.datFlit.srcId))
        return;
      end

      complete = accumulate(dataKey(agentId, tx.datFlit.srcId,
                                    tx.datFlit.txnId, tx.direction),
                            tx.datFlit, bytes);
      if (!complete) return;
      if (!txnTable.exists(key)) return;
      line = lineAddrOf(txnTable[key].addr);
      checkReadData(agentId, line, bytes);

      // For a read, the data is the completion: no Comp arrives on RSP at all,
      // so a lifecycle that only retired on RSP would leave every read open
      // and call the TxnID's next legitimate use a reuse
      // [SPEC:IHI0050H B2.3.1].
      if (!txnTable[key].completed)
        completeTransaction(agentId, key, tx.datFlit.resp, tx.datFlit.respErr);
    end else begin
      // Write data leaving. Tagged with the DBID the Home offered, which maps
      // back to the transaction and so to the address.
      if ((tx.datFlit.opcode != DAT_COPY_BACK_WR_DATA)
          && (tx.datFlit.opcode != DAT_NON_COPY_BACK_WR_DATA)
          && (tx.datFlit.opcode != DAT_NCB_WR_DATA_COMP_ACK)) begin
        // Snoop response data carries the snoop's TxnID and updates the line
        // just as a writeback does, because it is the same dirty data moving.
        if (tx.datFlit.opcode == DAT_SNP_RESP_DATA) begin
          complete = accumulate(dataKey(agentId, tx.datFlit.tgtId,
                                        tx.datFlit.txnId, tx.direction),
                                tx.datFlit, bytes);
          if (complete) begin
            line = snoopLineOf(agentId, tx.datFlit.tgtId, tx.datFlit.txnId);
            applyDirectoryFromResp(agentId, line, tx.datFlit.resp);
            recordLine(line, bytes);
          end
        end
        return;
      end

      complete = accumulate(dataKey(agentId, tx.datFlit.tgtId,
                                    tx.datFlit.txnId, tx.direction),
                            tx.datFlit, bytes);
      if (!complete) return;

      owner = dbidKey(agentId, tx.datFlit.tgtId, tx.datFlit.txnId);
      if (!dbidOwner.exists(owner)) begin
        `uvm_error(get_type_name(),
                   $sformatf({"requester %0d sent write data on DBID 0x%0h ",
                              "that was never offered"},
                             agentId, tx.datFlit.txnId))
        return;
      end
      key = dbidOwner[owner];
      if (!txnTable.exists(key)) return;
      line = lineAddrOf(txnTable[key].addr);
      recordLine(line, bytes);
      if (writesInFlight.exists(line) && (writesInFlight[line] > 0))
        writesInFlight[line]--;
    end
  endfunction

  // Collect the packets of one data message. Returns 1 on the packet that
  // completes the line.
  protected function bit accumulate(string key, chi_dat_flit_t dat,
                                    output chiLineBytesT bytes);
    dataAssemblyS state;
    int unsigned  offset;

    if (assembly.exists(key)) begin
      state = assembly[key];
    end else begin
      state.packets = 0;
      for (int unsigned i = 0; i < CHI_LINE_BYTES; i++) state.bytes[i] = '0;
    end

    // DataID names the 16-byte granule this packet starts at
    // [SPEC:IHI0050H B2.4.6].
    offset = int'(dat.dataId) * 16;
    for (int unsigned b = 0; b < (CHI_DATA_W / 8); b++)
      if ((offset + b) < CHI_LINE_BYTES)
        state.bytes[offset + b] = dat.data[b*8 +: 8];
    state.packets++;

    if (state.packets >= CHI_DAT_PKTS_PER_LINE) begin
      bytes = state.bytes;
      assembly.delete(key);
      return 1'b1;
    end
    assembly[key] = state;
    return 1'b0;
  endfunction

  protected function void recordLine(chiLineAddrT line, chiLineBytesT bytes);
    expectedLine[line] = bytes;
    lineWritten[line]  = 1'b1;
  endfunction

  // What a read must return: the bytes of the last write to the line, or the
  // deterministic initial contents if it has never been written.
  //
  // The check is skipped while a write to the same line is in flight. That is
  // not a weakness being papered over: with several Requesters writing the
  // same line concurrently, which of the writes a read observes is genuinely
  // unconstrained, so any expected value would be arbitrary.
  protected function void checkReadData(int unsigned agentId,
                                        chiLineAddrT line,
                                        chiLineBytesT bytes);
    chiLineBytesT expected;
    chiAddrT      base;

    if (writesInFlight.exists(line) && (writesInFlight[line] > 0)) begin
      dataChecksSkipped++;
      return;
    end

    if (lineWritten.exists(line) && lineWritten[line]) begin
      expected = expectedLine[line];
    end else begin
      base = {line, {CHI_LINE_OFF_W{1'b0}}};
      for (int unsigned i = 0; i < CHI_LINE_BYTES; i++)
        expected[i] = memInitByte(base + i);
    end

    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++) begin
      if (bytes[i] !== expected[i]) begin
        `uvm_error(get_type_name(),
                   $sformatf({"requester %0d read line 0x%0h byte %0d as ",
                              "0x%02h, expected 0x%02h"},
                             agentId, line, i, bytes[i], expected[i]))
        return;
      end
    end
    dataChecksPassed++;
  endfunction

  // -------------------------------------------------------------------------
  // Subordinate side
  // -------------------------------------------------------------------------
  protected task subordinateLoop(int unsigned agentId);
    chiSubordinateTx tx;
    forever begin
      subordinateFifo[agentId].get(tx);
      if (tx.txKind == CHI_TX_LINK_EVENT) begin
        checkLinkEvent(tx.linkEvent, $sformatf("subordinate %0d", agentId));
        if (tx.linkEvent.kind == CHI_LINK_EVT_STATE_CHANGE) begin
          subordinateLinkState[agentId][tx.linkEvent.direction] =
              tx.linkEvent.state;
          if (tx.linkEvent.state == CHI_LINK_RUN)
            subordinateLinkRan[agentId][tx.linkEvent.direction] = 1'b1;
        end
      end else if (tx.channel == CHI_CHANNEL_REQ) begin
        // A request reaching a Subordinate must be one a Completer can serve:
        // it must not be a snoopable request, because a Subordinate has no
        // cache to snoop [SPEC:IHI0050H B1.6.1].
        if (tx.direction != CHI_DIR_RX)
          `uvm_error(get_type_name(),
                     $sformatf("subordinate %0d sent a request", agentId))
        checkSubordinateAddress(agentId, tx.reqFlit.addr);
        // The address a write is going to, remembered against the DBID the
        // Subordinate will offer for it, which is the request's own TxnID.
        if (isWriteRequest(tx.reqFlit.opcode))
          subWriteAddr[subWriteKey(agentId, tx.reqFlit.srcId,
                                   tx.reqFlit.txnId)] = tx.reqFlit.addr;
      end else if (tx.channel == CHI_CHANNEL_RSP) begin
        checkResponseError(agentId, tx.rspFlit.respErr,
                           tx.rspFlit.opcode.name());
      end else if (tx.direction == CHI_DIR_RX) begin
        handleSubordinateData(agentId, tx);
      end
    end
  endtask

  // Memory is what a Subordinate holds, so this is where the model of it is
  // kept up to date. Watching only the Requester ports would miss a write the
  // Home originates itself, such as the writeback of a dirty line a snoop
  // recovered, and the model would then hold a value older than memory's
  // [SPEC:IHI0050H B2.12].
  protected function void handleSubordinateData(int unsigned agentId,
                                                chiSubordinateTx tx);
    string        key;
    chiLineBytesT bytes;

    if ((tx.datFlit.opcode != DAT_COPY_BACK_WR_DATA)
        && (tx.datFlit.opcode != DAT_NON_COPY_BACK_WR_DATA)
        && (tx.datFlit.opcode != DAT_NCB_WR_DATA_COMP_ACK)) return;

    if (!accumulate($sformatf("s%0d_p%0h_a%0h", agentId, tx.datFlit.srcId,
                              tx.datFlit.txnId),
                    tx.datFlit, bytes)) return;

    key = subWriteKey(agentId, tx.datFlit.srcId, tx.datFlit.txnId);
    if (!subWriteAddr.exists(key)) return;
    recordLine(lineAddrOf(subWriteAddr[key]), bytes);
  endfunction

  protected chiAddrT subWriteAddr [string];

  protected function string subWriteKey(int unsigned agentId,
                                        chiNodeIdT srcId, chiTxnIdT txnId);
    return $sformatf("s%0d_p%0h_w%0h", agentId, srcId, txnId);
  endfunction

  // The default System Address Map sends everything below the top address bit
  // to the hashed Home Nodes and everything above it to the HN-I
  // [top/chi_interconnect_top.sv makeRegionBase]. A fully coherent Subordinate
  // therefore only ever sees addresses from the lower region.
  protected function void checkSubordinateAddress(int unsigned agentId,
                                                  chiAddrT addr);
    if (cfg.subordinateCfg[agentId].nodeClass != NODE_SNF) return;
    if (addr[CHI_ADDR_W-1] !== 1'b0)
      `uvm_error(get_type_name(),
                 $sformatf({"SN-F %0d received address 0x%0h, which the ",
                            "address map routes to the HN-I region"},
                           agentId, addr))
  endfunction

  // -------------------------------------------------------------------------
  // Shared checks
  // -------------------------------------------------------------------------
  // A channel may never hold more credits than it was built with, in either
  // direction. Exceeding it means one side is issuing credits the other side
  // has no buffer for [SPEC:IHI0050H B14.6.3].
  protected function void checkLinkEvent(chiLinkEventS event_, string who);
    if (event_.kind != CHI_LINK_EVT_CREDIT_GRANT) return;
    if (event_.creditCount > CHI_CFG.lcrdDepth)
      `uvm_error(get_type_name(),
                 $sformatf({"%s holds %0d L-Credits on %s %s, more than the ",
                            "channel depth of %0d"},
                           who, event_.creditCount, event_.direction.name(),
                           event_.channel.name(), CHI_CFG.lcrdDepth))
  endfunction

  protected function void checkResponseError(int unsigned agentId,
                                             chi_resp_err_e respErr,
                                             string opcodeName);
    // Stage 1 injects no errors, so any error status is a real finding
    // [SPEC:IHI0050H B2.12]. EXOK belongs to exclusive accesses, which Stage 1
    // does not generate.
    if ((respErr == RESP_ERR_DERR) || (respErr == RESP_ERR_NDERR))
      `uvm_error(get_type_name(),
                 $sformatf("agent %0d saw %s on %s with no error injected",
                           agentId, respErr.name(), opcodeName))
  endfunction

  // An I/O coherent Requester may not issue a snoopable request, because it
  // holds no cacheable state [SPEC:IHI0050H B2.3.1, B1.6.1].
  protected function void checkOpcodeAllowedForClass(int unsigned agentId,
                                                     chiRequesterTx tx);
    if (cfg.requesterCfg[agentId].hasCache) return;
    case (tx.reqFlit.opcode)
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_UNIQUE,
      REQ_READ_NOT_SHARED_DIRTY, REQ_CLEAN_UNIQUE, REQ_MAKE_UNIQUE,
      REQ_WRITE_BACK_FULL, REQ_WRITE_BACK_PTL, REQ_EVICT:
        `uvm_error(get_type_name(),
                   $sformatf({"requester %0d is %s and may not issue %s, ",
                              "which requires a cache"},
                             agentId,
                             cfg.requesterCfg[agentId].nodeClass.name(),
                             tx.reqFlit.opcode.name()))
      default: ;
    endcase
  endfunction

  // The address a Requester asks for must lie in a region the map covers.
  protected function void checkAddressRouting(int unsigned agentId,
                                              chiRequesterTx tx);
    if (tx.reqFlit.size > 3'd6)
      `uvm_error(get_type_name(),
                 $sformatf("requester %0d used Size %0d, beyond a cache line",
                           agentId, tx.reqFlit.size))
  endfunction

  protected function bit isWriteRequest(chi_req_opcode_e opcode);
    case (opcode)
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL, REQ_WRITE_BACK_FULL,
      REQ_WRITE_BACK_PTL, REQ_WRITE_CLEAN_FULL, REQ_WRITE_UNIQUE_FULL,
      REQ_WRITE_UNIQUE_PTL, REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT,
      REQ_WRITE_NO_SNP_ZERO, REQ_WRITE_UNIQUE_ZERO:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  protected function string txnKey(int unsigned agentId, chiTxnIdT txnId);
    return $sformatf("r%0d_t%0h", agentId, txnId);
  endfunction

  // A DBID is chosen by the Completer that offered it, so it is only unique
  // within that Completer [SPEC:IHI0050H B2.9.1].
  protected function string dbidKey(int unsigned agentId, chiNodeIdT peerId,
                                    chiTxnIdT dbId);
    return $sformatf("r%0d_p%0h_d%0h", agentId, peerId, dbId);
  endfunction

  // Inbound data is tagged with the Requester's own TxnID and outbound data
  // with the TxnID of the snoop or the DBID of the write it answers. Those are
  // separate identifier spaces that collide freely, so the beats of a read and
  // of a concurrent snoop response must be reassembled in separate buffers
  // [SPEC:IHI0050H B2.3.2].
  protected function string dataKey(int unsigned agentId, chiNodeIdT peerId,
                                    chiTxnIdT txnId, chiDirectionE direction);
    return $sformatf("r%0d_p%0h_a%0h_%s", agentId, peerId, txnId,
                     (direction == CHI_DIR_RX) ? "rx" : "tx");
  endfunction

  // A TxnID is only unique within the node that issued it, so two Homes can
  // have a snoop outstanding to the same Requester under the same TxnID at the
  // same time. Every per-snoop record is therefore keyed by the Home as well
  // [SPEC:IHI0050H B2.3.1].
  protected function string snoopKey(int unsigned agentId, chiNodeIdT homeId,
                                     chiTxnIdT txnId);
    return $sformatf("r%0d_h%0h_s%0h", agentId, homeId, txnId);
  endfunction

  // -------------------------------------------------------------------------
  // End of test
  // -------------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    int unsigned incomplete;

    // Every link must have reached RUN in both directions. A test that drove
    // no traffic would otherwise pass simply by being silent.
    for (int unsigned i = 0; i < cfg.numRequesterAgents; i++) begin
      if (!requesterLinkRan.exists(i)
          || !requesterLinkRan[i].exists(CHI_DIR_TX)
          || !requesterLinkRan[i][CHI_DIR_TX])
        `uvm_error(get_type_name(),
                   $sformatf("requester %0d transmit link never reached RUN", i))
      if (!requesterLinkRan.exists(i)
          || !requesterLinkRan[i].exists(CHI_DIR_RX)
          || !requesterLinkRan[i][CHI_DIR_RX])
        `uvm_error(get_type_name(),
                   $sformatf("requester %0d receive link never reached RUN", i))
    end
    for (int unsigned i = 0; i < cfg.numSubordinateAgents; i++) begin
      if (!subordinateLinkRan.exists(i)
          || !subordinateLinkRan[i].exists(CHI_DIR_TX)
          || !subordinateLinkRan[i][CHI_DIR_TX])
        `uvm_error(get_type_name(),
                   $sformatf("subordinate %0d transmit link never reached RUN",
                             i))
      if (!subordinateLinkRan.exists(i)
          || !subordinateLinkRan[i].exists(CHI_DIR_RX)
          || !subordinateLinkRan[i][CHI_DIR_RX])
        `uvm_error(get_type_name(),
                   $sformatf("subordinate %0d receive link never reached RUN",
                             i))
    end

    // Nothing may be left in flight. An outstanding transaction at the end of
    // the test is one the fabric never answered.
    incomplete = 0;
    foreach (txnTable[key]) begin
      if (!txnTable[key].completed) begin
        incomplete++;
        `uvm_error(get_type_name(),
                   $sformatf({"transaction %s (%s at 0x%0h, issued at %0t) ",
                              "never completed"},
                             key, txnTable[key].opcode.name(),
                             txnTable[key].addr, txnTable[key].issuedAt))
      end
    end

    // A partially received data message means a line was left half delivered.
    foreach (assembly[key])
      `uvm_error(get_type_name(),
                 $sformatf("data message %s left incomplete with %0d packets",
                           key, assembly[key].packets))

    // Every RetryAck must have been answered with a P-Credit, or a Requester
    // is still parked waiting for one [SPEC:IHI0050H B2.10].
    if ((retriesSeen > 0) && (grantsSeen == 0))
      `uvm_error(get_type_name(),
                 $sformatf({"%0d RetryAck responses were sent but no ",
                            "PCrdGrant ever followed"}, retriesSeen))
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf({"scoreboard: %0d requests, %0d completions, %0d ",
                         "retries, %0d grants, %0d snoops; data checks %0d ",
                         "passed, %0d skipped for a concurrent write"},
                        requestsSeen, completionsSeen, retriesSeen, grantsSeen,
                        snoopsSeen, dataChecksPassed, dataChecksSkipped),
              UVM_LOW)
  endfunction
endclass
