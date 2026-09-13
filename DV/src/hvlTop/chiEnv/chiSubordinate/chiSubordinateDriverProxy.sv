// Subordinate protocol engine: a Completer that serves reads and writes out of
// its memory model.
//
// This is reactive. It originates nothing, so it does not pull stimulus items
// in the usual way; it answers whatever arrives. The sequencer is still there
// and is consulted, but without blocking: a sequence can supply a response
// policy such as an added latency, and when no sequence is running the
// configured defaults apply. Blocking on the sequencer would be wrong, because
// a Subordinate that stopped answering because no sequence was running would
// hang the whole fabric rather than idle.
//
// The Home Node forwards the Requester's own opcode downstream rather than
// translating it to ReadNoSnp [hnf/chi_hnf_top.sv downstreamReq], so this
// model classifies whatever opcode arrives instead of expecting one particular
// one.
class chiSubordinateDriverProxy extends uvm_driver #(chiSubordinateTx);

  chiSubordinateAgentConfig       cfg;
  virtual chiSubordinateDriverBfm bfm;
  chiSubordinateMemoryModel       memory;

  uvm_analysis_port #(chiSubordinateTx) apPort;

  protected semaphore concurrencySem;

  // DBID names the buffer this Subordinate offers for a write, and the write
  // data comes back tagged with it [SPEC:IHI0050H B2.3.1]. The value echoes the
  // request's TxnID rather than being allocated freely, because the Home Node
  // rewrites the TxnID of the write data it relays to the original request's
  // TxnID [hnf/chi_hnf_top.sv requesterDat.txnId], so a DBID chosen any other
  // way could never be matched to the data that arrives.
  //
  // Echoing the TxnID means it is only unique per sending Home, so the waiting
  // requests are keyed on source and TxnID together: two Homes may have the
  // same TxnID outstanding at the same time.
  protected mailbox #(chi_dat_flit_t) writeDataMbox [string];

  protected int unsigned readsServed;
  protected int unsigned writesServed;
  protected int unsigned otherServed;

  `uvm_component_utils(chiSubordinateDriverProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    apPort = new("apPort", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    concurrencySem = new(cfg.maxConcurrentRequests);
  endfunction

  task run_phase(uvm_phase phase);
    bfm.bringUp();
    `uvm_info(get_type_name(),
              $sformatf("%s brought up: %s", cfg.nodeClass.name(),
                        cfg.convert2string()), UVM_LOW)
    fork
      requestLoop();
      writeDataRouter();
      unexpectedResponseLoop();
    join
  endtask

  // -------------------------------------------------------------------------
  // Request service
  // -------------------------------------------------------------------------
  protected task requestLoop();
    chi_req_flit_t req;
    forever begin
      bfm.getRequest(req);
      concurrencySem.get(1);
      fork
        automatic chi_req_flit_t served = req;
        begin
          serveRequest(served);
          concurrencySem.put(1);
        end
      join_none
      #0;
    end
  endtask

  protected task serveRequest(chi_req_flit_t req);
    chiSubordinateTx policy;

    currentPolicy(policy);
    if (policy.responseDelay > 0) bfm.waitCycles(policy.responseDelay);

    if (isReadOpcode(req.opcode)) begin
      serveRead(req, policy);
      readsServed++;
    end else if (isWriteOpcode(req.opcode)) begin
      serveWrite(req, policy);
      writesServed++;
    end else begin
      // A request that moves no data still has to be completed, or the Home
      // Node waits for a response that never comes.
      serveCompletionOnly(req, policy);
      otherServed++;
    end
  endtask

  // A read is answered with the line from memory, split across as many DAT
  // packets as the data bus needs [SPEC:IHI0050H B2.9.4].
  protected task serveRead(chi_req_flit_t req, chiSubordinateTx policy);
    chi_dat_flit_t dat;
    chiLineBytesT  bytes;

    bytes = memory.readLine(req.addr);

    for (int unsigned p = 0; p < CHI_DAT_PKTS_PER_LINE; p++) begin
      dat         = '0;
      dat.qos     = req.qos;
      dat.tgtId   = req.srcId;
      dat.srcId   = cfg.nodeId;
      dat.txnId   = req.txnId;
      // HomeNID and DBID let the Requester address its CompAck. With no direct
      // transfer in Stage 1 the read is answered to the Home, which needs
      // neither, but they are filled in so the flit is well formed.
      dat.homeNidOrPbha = req.srcId;
      dat.dbId          = CHI_DAT_DBID_SLOT_W'(req.txnId);
      dat.opcode        = DAT_COMP_DATA;
      // A Subordinate has no notion of coherent state, so a read it answers
      // grants the line clean and unique unless the Home says otherwise
      // [SPEC:IHI0050H B4.4].
      dat.resp    = RESP_UC_UD;
      dat.respErr = policy.injectError;
      dat.dataId  = CHI_DATAID_SLOT_W'(p * datIdStep(CHI_CFG));
      dat.be      = {64{1'b1}};
      dat.data    = lineToDataAt(bytes, p);
      dat.numDat  = '0;
      bfm.sendData(dat);
    end
  endtask

  // A write is answered by offering a buffer, then taking the data, then
  // reporting completion, as three separate steps.
  //
  // The buffer offer and the completion are deliberately not combined into one
  // CompDBIDResp. The spec permits combining them, but the Home Node in front
  // of this Subordinate holds no write buffer of its own: it relays the
  // Requester's data through while it is still waiting for this Subordinate's
  // response, and it decides where an arriving data flit belongs by comparing
  // it against the one request it has active [hnf/chi_hnf_top.sv
  // requesterDat.tgtId]. Completing early releases the Home before the
  // Requester, which cannot send data until it has the DBID, has sent any. The
  // data then arrives with the Home serving somebody else and is delivered to
  // that unrelated Requester instead. Sending Comp only after the data has
  // arrived keeps the Home in its waiting state for exactly as long as the data
  // is in flight [SPEC:IHI0050H B2.3.1].
  protected task serveWrite(chi_req_flit_t req, chiSubordinateTx policy);
    chi_rsp_flit_t rsp;
    chi_dat_flit_t dat;
    string         key;
    chiLineBytesT  bytes;
    int unsigned   received;
    int unsigned   offset;
    bit            cancelled;
    logic [CHI_LINE_BYTES-1:0] byteEnable;

    key                = writeKey(req.srcId, req.txnId);
    writeDataMbox[key] = new();

    rsp                = '0;
    rsp.qos            = req.qos;
    rsp.tgtId          = req.srcId;
    rsp.srcId          = cfg.nodeId;
    rsp.txnId          = req.txnId;
    rsp.opcode         = RSP_DBID_RESP;
    rsp.resp           = RESP_I;
    rsp.respErr        = policy.injectError;
    rsp.dbIdOrGroupId  = CHI_RSP_DBID_SLOT_W'(req.txnId);
    bfm.sendResponse(rsp);

    cancelled  = 1'b0;
    received   = 0;
    byteEnable = '0;
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++) bytes[i] = '0;

    // A zero write carries no data at all, so there is nothing to wait for
    // [SPEC:IHI0050H B2.3.1].
    if ((req.opcode == REQ_WRITE_NO_SNP_ZERO)
        || (req.opcode == REQ_WRITE_UNIQUE_ZERO)) begin
      memory.writeLine(req.addr, bytes);
    end else begin
      while (received < CHI_DAT_PKTS_PER_LINE) begin
        writeDataMbox[key].get(dat);
        // A cancelled write carries no data and must leave memory untouched
        // [SPEC:IHI0050H B2.9.3].
        if (dat.opcode == DAT_WRITE_DATA_CANCEL) begin
          cancelled = 1'b1;
          break;
        end
        offset = int'(dat.dataId) * 16;
        for (int unsigned b = 0; b < (CHI_DATA_W / 8); b++) begin
          if ((offset + b) < CHI_LINE_BYTES) begin
            bytes[offset + b]      = dat.data[b*8 +: 8];
            byteEnable[offset + b] = dat.be[b];
          end
        end
        received++;
      end

      // Byte enables are honoured so a partial write leaves the rest of the
      // line alone.
      if (!cancelled)
        memory.writeLineMasked(req.addr, bytes, byteEnable);
    end

    writeDataMbox.delete(key);

    // Comp closes the write now that the data is in memory. The Home converts
    // this into the CompDBIDResp the Requester sees
    // [hnf/chi_hnf_top.sv COMBINED_COMP_DBID].
    rsp.opcode        = RSP_COMP;
    rsp.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(req.txnId);
    bfm.sendResponse(rsp);
  endtask

  protected task serveCompletionOnly(chi_req_flit_t req,
                                     chiSubordinateTx policy);
    chi_rsp_flit_t rsp;
    rsp         = '0;
    rsp.qos     = req.qos;
    rsp.tgtId   = req.srcId;
    rsp.srcId   = cfg.nodeId;
    rsp.txnId   = req.txnId;
    rsp.opcode  = RSP_COMP;
    rsp.resp    = RESP_I;
    rsp.respErr = policy.injectError;
    bfm.sendResponse(rsp);
    `uvm_info(get_type_name(),
              $sformatf("completed %s at 0x%0h with no data movement",
                        req.opcode.name(), req.addr), UVM_HIGH)
  endtask

  // -------------------------------------------------------------------------
  // Write data routing
  // -------------------------------------------------------------------------
  // Write data arrives tagged with the DBID this Subordinate handed out, so it
  // is routed to the request waiting for it.
  protected task writeDataRouter();
    chi_dat_flit_t dat;
    string         key;
    forever begin
      bfm.getData(dat);
      key = writeKey(dat.srcId, dat.txnId);
      if (writeDataMbox.exists(key))
        writeDataMbox[key].put(dat);
      else
        `uvm_error(get_type_name(),
                   $sformatf({"write data for unknown DBID 0x%0h from 0x%0h: ",
                              "%s"}, dat.txnId, dat.srcId, dat.opcode.name()))
    end
  endtask

  // The receive response channel is credited so that link activation can
  // complete, but the spec shows no protocol response arriving at a
  // Subordinate. Anything that does arrive is a finding, not something to
  // drop silently. See OPEN QUESTIONS.
  protected task unexpectedResponseLoop();
    chi_rsp_flit_t rsp;
    forever begin
      bfm.getResponse(rsp);
      `uvm_error(get_type_name(),
                 $sformatf("unexpected response at a Subordinate: %s from 0x%0h",
                           rsp.opcode.name(), rsp.srcId))
    end
  endtask

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  protected function string writeKey(chiNodeIdT srcId, chiTxnIdT txnId);
    return $sformatf("%0h_%0h", srcId, txnId);
  endfunction

  // Response policy from the sequencer if a sequence is offering one, and the
  // configured default otherwise. try_next_item never blocks, which is what
  // keeps an idle sequencer from stalling the memory.
  // A task rather than a function because try_next_item is itself a task,
  // even though it never blocks.
  protected task currentPolicy(output chiSubordinateTx policy);
    chiSubordinateTx item;
    seq_item_port.try_next_item(item);
    if (item != null) begin
      policy = item;
      seq_item_port.item_done();
      return;
    end
    policy               = chiSubordinateTx::type_id::create("defaultPolicy");
    policy.responseDelay = cfg.defaultResponseDelay;
    policy.injectError   = RESP_ERR_OK;
  endtask

  protected function bit isReadOpcode(chi_req_opcode_e opcode);
    case (opcode)
      REQ_READ_NO_SNP, REQ_READ_NO_SNP_SEP, REQ_READ_ONCE, REQ_READ_SHARED,
      REQ_READ_CLEAN, REQ_READ_UNIQUE, REQ_READ_NOT_SHARED_DIRTY,
      REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID,
      REQ_READ_PREFER_UNIQUE, REQ_MAKE_READ_UNIQUE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  protected function bit isWriteOpcode(chi_req_opcode_e opcode);
    case (opcode)
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL, REQ_WRITE_BACK_FULL,
      REQ_WRITE_BACK_PTL, REQ_WRITE_CLEAN_FULL, REQ_WRITE_UNIQUE_FULL,
      REQ_WRITE_UNIQUE_PTL, REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT,
      REQ_WRITE_NO_SNP_ZERO, REQ_WRITE_UNIQUE_ZERO, REQ_WRITE_NO_SNP_DEF:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  protected function chiDataT lineToDataAt(chiLineBytesT bytes,
                                           int unsigned packetIndex);
    chiDataT     value;
    int unsigned base;
    value = '0;
    base  = packetIndex * (CHI_DATA_W / 8);
    for (int unsigned b = 0; b < (CHI_DATA_W / 8); b++)
      if ((base + b) < CHI_LINE_BYTES)
        value[b*8 +: 8] = bytes[base + b];
    return value;
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf({"%s agent %0d: %0d reads, %0d writes, %0d other ",
                         "served, %s"},
                        cfg.nodeClass.name(), cfg.agentId, readsServed,
                        writesServed, otherServed,
                        (memory != null) ? memory.convert2string()
                                         : "no memory"),
              UVM_LOW)
  endfunction
endclass
