// Pin traffic for one Subordinate port.
//
// A Subordinate is reactive, so there is no equivalent of the requester's
// mainLoop pulling intent off a sequencer and turning it into a request.
// Work arrives on the wire. Three threads share it: reqLoop accepts requests
// and hands them to a worker pool, datLoop folds write data into the store,
// and ruleLoop collects response-policy items so a worker never blocks on
// the sequencer.
//
// Every response shape below comes from one of the five Home to Subordinate
// flow figures, and each is cited where it is built. The point of following
// them exactly is that the Subordinate is the DUT's other side: if this
// model answers in a shape the DUT does not expect, the failure looks like a
// DUT bug and costs a debug cycle to disprove.
// [SPEC:IHI0050H B2.3.9 Home to Subordinate transactions]

class chiSubordinateDriverProxy extends uvm_driver#(chiSubordinateTx);
  virtual chiSubordinateDriverBfm bfm;
  chiSubordinateConfig cfg;
  chiSubordinateMemory mem;
  chiSubordinateCoverage cov;

  semaphore dbIdGuard;
  semaphore ruleGuard;
  semaphore lineGuard;
  mailbox #(chiReqFlitT) reqMb;
  chiTxnIdT freeDbId[$];
  chiSubordinateTxnContext ctxByDbId[chiTxnIdT];
  chiSubordinateTx rules[$];
  semaphore lineLock[chiAddrT];

  // Protocol credits this port has granted and not yet seen spent. Keyed by
  // requester and credit type, because a grant is only good for the pair.
  semaphore pcrdGuard;
  int unsigned pcrdCount[chiPcrdKeyT];

  int unsigned prefetchTgtSeen;

  `uvm_component_utils(chiSubordinateDriverProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    prefetchTgtSeen = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);
    if (!uvm_config_db#(chiSubordinateConfig)::get(this, "", "chiSubordinateConfig", cfg))
      `uvm_fatal("chiSubordinateConfig", "config_db get failed for key chiSubordinateConfig")
    cfg.chiNormalize();
    key = cfg.driverKey();
    if (!uvm_config_db#(virtual chiSubordinateDriverBfm)::get(this, "", key, bfm))
      `uvm_fatal("chiSubordinateDriverProxy", {"config_db get failed for key ", key})
    // The store is shared across every Subordinate port because the DUT, not
    // the testbench, decides which port an address lands on.
    if (!uvm_config_db#(chiSubordinateMemory)::get(this, "", "chiSubordinateMemory", mem))
      `uvm_fatal("chiSubordinateMemory", "config_db get failed for key chiSubordinateMemory")
    dbIdGuard = new(1);
    ruleGuard = new(1);
    lineGuard = new(1);
    pcrdGuard = new(1);
    reqMb = new();
    for (int unsigned id = 0; id < cfg.outstandingCap; id++)
      freeDbId.push_back(chiTxnIdT'(id));
  endfunction

  task run_phase(uvm_phase phase);
    bfm.waitConfigured();
    bfm.linkInit();
    if (cfg.holdQuiet) begin
      wait(0);
      return;
    end
    bfm.linkStart();
    bfm.linkActivate();
    fork
      reqLoop();
      datLoop();
      ruleLoop();
    join_none
    for (int unsigned worker = 0; worker < cfg.outstandingCap; worker++) begin
      fork
        begin
          automatic int unsigned workerId = worker;
          chiWorker(workerId);
        end
      join_none
    end
    wait(0);
  endtask

  task shutdown_phase(uvm_phase phase);
    if (cfg.holdQuiet)
      return;
    bfm.linkDeactivate();
  endtask

  //----------------------------------------------------------------------------
  // Intake
  //----------------------------------------------------------------------------

  task automatic reqLoop();
    chiRawFlitT raw;
    chiReqFlitT flit;
    forever begin
      bfm.getReqFlit(raw);
      if (isLcrdReturn(CHI_CH_REQ, raw))
        continue;
      flit = unpackReq(raw);
      reqMb.put(flit);
    end
  endtask

  task automatic chiWorker(input int unsigned workerId);
    chiReqFlitT flit;
    if (workerId >= cfg.outstandingCap)
      return;
    forever begin
      reqMb.get(flit);
      chiServeRequest(flit);
    end
  endtask

  // Response policy is collected in the background so that a worker deciding
  // how to answer never waits on a sequence that may have nothing to say.
  task automatic ruleLoop();
    chiSubordinateTx item;
    forever begin
      seq_item_port.get_next_item(item);
      ruleGuard.get(1);
      rules.push_back(item);
      ruleGuard.put(1);
      seq_item_port.item_done();
    end
  endtask

  // First matching rule wins, and a rule with a use count retires when it is
  // exhausted. Returns null when nothing matched, meaning config defaults.
  // No lock is taken: a function body contains no blocking statement, so it
  // runs to completion before ruleLoop can append to the queue.
  function chiSubordinateTx chiPickRule(input chiAddrT addr, input chiReqOpcodeE opcode);
    chiSubordinateTx hit;
    hit = null;
    foreach (rules[i]) begin
      if (!rules[i].chiMatches(addr, opcode))
        continue;
      hit = rules[i];
      hit.lastMatchAddr = addr;
      hit.lastMatchOpcode = opcode;
      if (hit.useCount > 0) begin
        hit.useCount--;
        if (hit.useCount == 0)
          rules.delete(i);
      end
      break;
    end
    return hit;
  endfunction

  //----------------------------------------------------------------------------
  // Request classification
  //
  // The permitted request set is not a matter of taste: Tables B4.2, B4.3,
  // B4.9, B4.16, B4.17, B4.24 and B4.25 say exactly what a Home may send to
  // an SN-F and to an SN-I, and B4.20 bounds the Combined Write set. A
  // request outside that set is a DUT bug, so it is reported rather than
  // answered on a guess.
  //----------------------------------------------------------------------------

  function bit chiIsPlainWrite(input chiReqOpcodeE opcode);
    return opcode inside {REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL, REQ_WRITE_NO_SNP_DEF};
  endfunction

  function bit chiIsWriteZero(input chiReqOpcodeE opcode);
    return opcode == REQ_WRITE_NO_SNP_ZERO;
  endfunction

  // The nine Combined Write and CMO requests a Home may send to a
  // Subordinate. [SPEC:IHI0050H B2.3.9.4 Figure B2.18] [SPEC:IHI0050H B4.20]
  function bit chiIsCombinedWrite(input chiReqOpcodeE opcode);
    return opcode inside {
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV, REQ_WRITE_NO_SNP_FULL_CLEAN_INV,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH, REQ_WRITE_NO_SNP_FULL_CLEAN_SH,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP, REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA, REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG};
  endfunction

  // Of those nine, the three whose CMO half needs a separate Persist.
  function bit chiCombinedCmoIsPersist(input chiReqOpcodeE opcode);
    return opcode inside {REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP,
                          REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP};
  endfunction

  // [SPEC:IHI0050H B4.2 Table B4.9 HN-F to SN-F Dataless requests]
  function bit chiIsDataless(input chiReqOpcodeE opcode);
    return opcode inside {REQ_CLEAN_SHARED, REQ_CLEAN_SHARED_PERSIST,
                          REQ_CLEAN_SHARED_PERSIST_SEP, REQ_CLEAN_INVALID,
                          REQ_CLEAN_INVALID_POPA, REQ_CLEAN_INVALID_STORAGE,
                          REQ_MAKE_INVALID};
  endfunction

  function bit chiIsAtomicStore(input chiReqOpcodeE opcode);
    return (opcode >= REQ_ATOMIC_STORE_ADD) && (opcode <= REQ_ATOMIC_STORE_UMIN);
  endfunction

  function bit chiIsAtomicReturning(input chiReqOpcodeE opcode);
    return ((opcode >= REQ_ATOMIC_LOAD_ADD) && (opcode <= REQ_ATOMIC_LOAD_UMIN))
           || (opcode == REQ_ATOMIC_SWAP) || (opcode == REQ_ATOMIC_COMPARE);
  endfunction

  // SN-I never receives ReadNoSnpSep: Table B4.3 lists only ReadNoSnp for
  // the HN-I to SN-I pair, where Table B4.2 lists both for HN-F to SN-F.
  function bit chiIsLegalHere(input chiReqOpcodeE opcode);
    if (opcode == REQ_READ_NO_SNP)
      return 1'b1;
    if (opcode == REQ_READ_NO_SNP_SEP)
      return cfg.nodeClass == SN_F;
    if (opcode == REQ_PREFETCH_TGT)
      return cfg.nodeClass == SN_F;
    if (chiIsPlainWrite(opcode) || chiIsWriteZero(opcode) || chiIsCombinedWrite(opcode))
      return 1'b1;
    if (chiIsDataless(opcode))
      return 1'b1;
    if (chiIsAtomicStore(opcode) || chiIsAtomicReturning(opcode))
      return 1'b1;
    return 1'b0;
  endfunction

  //----------------------------------------------------------------------------
  // Dispatch
  //----------------------------------------------------------------------------

  task automatic chiServeRequest(input chiReqFlitT req);
    chiSubordinateTx rule;

    // A returned credit is not a request and carries no work.
    if (req.opcode == REQ_P_CRD_RETURN) begin
      chiConsumeCredit(req, 1'b1);
      return;
    end

    // Retry comes before anything else: a retried request is not served at
    // all, it is refused and the credit to resend is granted instead.
    // [SPEC:IHI0050H B2.12 Transaction retry]
    if (cfg.enableRetry && req.allowRetry) begin
      chiSendRetry(req);
      return;
    end
    // A request that has given up its right to be retried must be spending a
    // credit this port granted. If no such credit is outstanding, either the
    // DUT invented one or it dropped a RetryAck.
    if (!req.allowRetry)
      chiConsumeCredit(req, 1'b0);

    rule = chiPickRule(req.addr, req.opcode);
    if (cov != null)
      cov.sampleRequest(req, rule);

    if (!chiIsLegalHere(req.opcode)) begin
      `uvm_error("chiSubordinateDriverProxy",
        $sformatf({"%s received %s, which Tables B4.2, B4.3, B4.9, B4.16, B4.17 ",
                   "and B4.24 do not permit a Home to send to this node class"},
                  nodeClassName(cfg.nodeClass), req.opcode.name()))
      return;
    end

    // PrefetchTgt is a hint with no response of any kind, so the only right
    // answer is silence. Counting it lets a test assert the DUT sent one and
    // then made progress without waiting.
    // [SPEC:IHI0050H C4.30 PrefetchTgt]
    if (req.opcode == REQ_PREFETCH_TGT) begin
      prefetchTgtSeen++;
      if (!cfg.dropPrefetchTgt)
        `uvm_info("chiSubordinateDriverProxy",
          $sformatf("PrefetchTgt for %0h ignored", req.addr), UVM_HIGH)
      return;
    end

    if (req.opcode inside {REQ_READ_NO_SNP, REQ_READ_NO_SNP_SEP})
      chiServeRead(req, rule);
    else if (chiIsDataless(req.opcode))
      chiServeDataless(req, rule);
    else if (chiIsAtomicReturning(req.opcode))
      chiServeAtomicReturning(req, rule);
    else
      chiServeWrite(req, rule);
  endtask

  //----------------------------------------------------------------------------
  // Reads. ReadNoSnp is answered with CompData, ReadNoSnpSep with
  // DataSepResp. The Subordinate does not choose between them; the opcode
  // does. ReadReceipt is the only optional part, and only when Order is
  // non-zero. [SPEC:IHI0050H B2.3.9.1 Figure B2.15]
  //----------------------------------------------------------------------------

  task automatic chiServeRead(input chiReqFlitT req, input chiSubordinateTx rule);
    logic [511:0] value;
    chiRespErrE err;
    int unsigned beats;
    bit wantReceipt;
    chiDatOpcodeE datOpcode;

    err = (rule != null) ? rule.respErr : cfg.defaultRespErr;
    wantReceipt = cfg.sendReadReceipt && ((rule == null) || !rule.suppressReadReceipt);

    if ((req.order != '0) && wantReceipt) begin
      chiWaitResponse(rule);
      chiSendReadReceipt(req);
    end

    chiWaitResponse(rule);
    chiLockLine(lineAlign(req.addr));
    value = mem.chiReadLine(req.addr);
    chiUnlockLine(lineAlign(req.addr));

    // Corruption with RespErr still OK is the case an end-to-end data check
    // has to catch by itself, so it is a separate knob from respErr.
    if ((rule != null) && rule.corruptReadData)
      value[0] = ~value[0];

    datOpcode = (req.opcode == REQ_READ_NO_SNP_SEP) ? DAT_DATA_SEP_RESP : DAT_COMP_DATA;
    beats = datPacketCount(req.size);
    for (int unsigned beat = 0; beat < beats; beat++)
      chiSendData(req, datOpcode, value, beat, beats, err);
  endtask

  //----------------------------------------------------------------------------
  // Retry and Protocol credits
  //----------------------------------------------------------------------------

  // RetryAck refuses the request, PCrdGrant then tells the Requester it may
  // resend with AllowRetry clear. Sent back to back here because this model
  // has no real resource to wait for; the delay between them is what a test
  // varies when it wants to stress the Requester's retry queue.
  task automatic chiSendRetry(input chiReqFlitT req);
    chiRspFlitT flit;
    chiPcrdKeyT key;

    flit = chiBlankRsp();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.txnId = req.txnId;
    flit.opcode = RSP_RETRY_ACK;
    flit.respErr = RESP_ERR_OK;
    flit.pCrdType = req.pCrdType;
    flit.traceTag = req.traceTag;
    bfm.driveRsp(flit);

    flit.opcode = RSP_P_CRD_GRANT;
    bfm.driveRsp(flit);

    key.srcId = req.srcId;
    key.pcrdType = req.pCrdType;
    pcrdGuard.get(1);
    if (!pcrdCount.exists(key))
      pcrdCount[key] = 0;
    pcrdCount[key]++;
    pcrdGuard.put(1);
  endtask

  // quiet is set for an explicit PCrdReturn, where finding no credit means
  // the DUT returned one it was never granted, and that is reported by the
  // caller rather than here.
  task automatic chiConsumeCredit(input chiReqFlitT req, input bit quiet);
    chiPcrdKeyT key;
    bit missing;
    key.srcId = req.srcId;
    key.pcrdType = req.pCrdType;
    missing = 1'b1;
    pcrdGuard.get(1);
    if (pcrdCount.exists(key) && (pcrdCount[key] > 0)) begin
      pcrdCount[key]--;
      missing = 1'b0;
    end
    pcrdGuard.put(1);
    if (missing && !quiet && cfg.enableRetry)
      `uvm_error("chiSubordinateDriverProxy",
        $sformatf("AllowRetry is 0 from src %0h pCrdType %0h but this port granted no such credit",
                  req.srcId, req.pCrdType))
  endtask

  task automatic chiSendReadReceipt(input chiReqFlitT req);
    chiRspFlitT rsp;
    rsp = chiBlankRsp();
    rsp.tgtId = req.srcId;
    rsp.txnId = req.txnId;
    rsp.opcode = RSP_READ_RECEIPT;
    rsp.respErr = RESP_ERR_OK;
    if (cov != null)
      cov.sampleResponse(RSP_READ_RECEIPT, RESP_ERR_OK, 1'b0);
    bfm.driveRsp(rsp);
  endtask

  //----------------------------------------------------------------------------
  // Dataless CMOs. Comp for all of them, except CleanSharedPersistSep, which
  // needs a Persist as well and may combine the two into CompPersist.
  // [SPEC:IHI0050H B2.3.9.5 Figure B2.19]
  //----------------------------------------------------------------------------

  task automatic chiServeDataless(input chiReqFlitT req, input chiSubordinateTx rule);
    chiRespErrE err;
    bit separate;
    err = (rule != null) ? rule.respErr : cfg.defaultRespErr;
    separate = (rule != null) ? rule.forceSeparateWriteResp : !cfg.combinedWriteResp;

    chiWaitResponse(rule);
    if (req.opcode != REQ_CLEAN_SHARED_PERSIST_SEP) begin
      chiSendSimpleRsp(req, RSP_COMP, err, '0);
      return;
    end
    if (separate) begin
      chiSendSimpleRsp(req, RSP_COMP, err, '0);
      chiWaitResponse(rule);
      chiSendSimpleRsp(req, RSP_PERSIST, err, '0);
    end
    else begin
      chiSendSimpleRsp(req, RSP_COMP_PERSIST, err, '0);
    end
  endtask

  //----------------------------------------------------------------------------
  // Writes, write zero, combined write and CMO, and AtomicStore. These four
  // share the DBID handshake, so they share one task and differ only in what
  // happens after the data arrives.
  // [SPEC:IHI0050H B2.3.9.2 Figure B2.16] [SPEC:IHI0050H B2.3.9.3 Figure B2.17]
  // [SPEC:IHI0050H B2.3.9.4 Figure B2.18] [SPEC:IHI0050H B2.3.9.6 Figure B2.20]
  //----------------------------------------------------------------------------

  task automatic chiServeWrite(input chiReqFlitT req, input chiSubordinateTx rule);
    chiSubordinateTxnContext ctx;
    chiRespErrE err;
    bit separate;
    bit isZero;
    int wake;

    err = (rule != null) ? rule.respErr : cfg.defaultRespErr;
    separate = (rule != null) ? rule.forceSeparateWriteResp : !cfg.combinedWriteResp;
    isZero = chiIsWriteZero(req.opcode);

    ctx = new();
    ctx.req = req;
    ctx.beatsExpected = isZero ? 0 : datPacketCount(req.size);
    chiAllocDbId(ctx);

    chiWaitResponse(rule);
    if (separate) begin
      chiSendSimpleRsp(req, RSP_DBID_RESP, err, ctx.dbId);
      chiWaitResponse(rule);
      chiSendSimpleRsp(req, RSP_COMP, err, ctx.dbId);
    end
    else begin
      chiSendSimpleRsp(req, RSP_COMP_DBID_RESP, err, ctx.dbId);
    end

    if (isZero) begin
      // No data transfer at all: the request alone says to zero the line.
      chiLockLine(lineAlign(req.addr));
      mem.chiWriteZero(req.addr);
      chiUnlockLine(lineAlign(req.addr));
    end
    else begin
      while (!ctx.chiDataComplete())
        ctx.ping.get(wake);
    end

    if (chiIsCombinedWrite(req.opcode)) begin
      chiWaitResponse(rule);
      if (!chiCombinedCmoIsPersist(req.opcode))
        chiSendSimpleRsp(req, RSP_COMP_CMO, err, ctx.dbId);
      else if (separate) begin
        chiSendSimpleRsp(req, RSP_COMP_CMO, err, ctx.dbId);
        chiWaitResponse(rule);
        chiSendSimpleRsp(req, RSP_PERSIST, err, ctx.dbId);
      end
      else
        chiSendSimpleRsp(req, RSP_COMP_PERSIST, err, ctx.dbId);
    end

    chiFreeDbId(ctx);
  endtask

  //----------------------------------------------------------------------------
  // AtomicLoad, AtomicSwap and AtomicCompare. Unlike AtomicStore these have
  // no combined response: DBIDResp, then the operand arrives, then CompData
  // carrying the value from before the operation.
  // [SPEC:IHI0050H B2.3.9.6 Figure B2.20 alternative 2]
  //----------------------------------------------------------------------------

  task automatic chiServeAtomicReturning(input chiReqFlitT req, input chiSubordinateTx rule);
    chiSubordinateTxnContext ctx;
    chiRespErrE err;
    logic [511:0] priorValue;
    logic [511:0] updated;
    int unsigned beats;
    int wake;

    err = (rule != null) ? rule.respErr : cfg.defaultRespErr;
    ctx = new();
    ctx.req = req;
    ctx.beatsExpected = datPacketCount(req.size);
    chiAllocDbId(ctx);

    chiWaitResponse(rule);
    chiSendSimpleRsp(req, RSP_DBID_RESP, err, ctx.dbId);

    while (!ctx.chiDataComplete())
      ctx.ping.get(wake);

    chiLockLine(lineAlign(req.addr));
    priorValue = mem.chiReadLine(req.addr);
    updated = chiAtomicApply(req, priorValue, ctx.gathered);
    mem.chiPreloadLine(req.addr, updated);
    chiUnlockLine(lineAlign(req.addr));

    // The returned value is the one from before the operation.
    chiWaitResponse(rule);
    beats = datPacketCount(req.size);
    for (int unsigned beat = 0; beat < beats; beat++)
      chiSendData(req, DAT_COMP_DATA, priorValue, beat, beats, err);
    chiFreeDbId(ctx);
  endtask

  //----------------------------------------------------------------------------
  // Write data arrival
  //----------------------------------------------------------------------------

  task automatic datLoop();
    chiRawFlitT raw;
    chiDatFlitT flit;
    forever begin
      bfm.getDatFlit(raw);
      if (isLcrdReturn(CHI_CH_DAT, raw))
        continue;
      flit = unpackDat(raw);
      chiNoteWriteData(flit);
    end
  endtask

  task automatic chiNoteWriteData(input chiDatFlitT flit);
    chiSubordinateTxnContext ctx;
    bit found;
    int unsigned byteOffset;

    dbIdGuard.get(1);
    found = ctxByDbId.exists(flit.txnId);
    if (found)
      ctx = ctxByDbId[flit.txnId];
    dbIdGuard.put(1);
    if (!found) begin
      `uvm_error("chiSubordinateDriverProxy",
        $sformatf("DAT with TxnID %0h opcode %s matches no DBID this Subordinate handed out",
                  flit.txnId, flit.opcode.name()))
      return;
    end

    if (cov != null)
      cov.sampleWriteData(flit, flit.be == {BE_W{1'b1}});

    // A cancellation replaces the whole transfer: nothing is written.
    // [SPEC:IHI0050H C4.57 WriteDataCancel]
    if (flit.opcode == DAT_WRITE_DATA_CANCEL) begin
      ctx.cancelled = 1'b1;
      ctx.ping.put(1);
      return;
    end

    // A sender may carry fewer packets than Size implies and say so in
    // NumDat, so the expected count is revised rather than assumed.
    if (flit.numDat != '0)
      ctx.beatsExpected = int'(flit.numDat);

    byteOffset = int'(flit.dataId) * (128 / 8);
    ctx.gathered[byteOffset*8 +: DATA_W] = flit.data;
    if (!chiIsAtomicReturning(ctx.req.opcode) && !chiIsAtomicStore(ctx.req.opcode)) begin
      chiLockLine(lineAlign(ctx.req.addr));
      mem.chiWriteBeat(ctx.req.addr, byteOffset, flit.data, flit.be, flit.poison);
      chiUnlockLine(lineAlign(ctx.req.addr));
    end
    ctx.beatsSeen++;
    ctx.ping.put(1);
  endtask

  //----------------------------------------------------------------------------
  // Atomic arithmetic.
  //
  // Written here rather than shared with topAtomicRefModel on purpose: the
  // scoreboard's prediction has to be able to disagree with what this model
  // did, and a single shared implementation would make a wrong answer agree
  // with itself. The two are deliberately written differently.
  // [SPEC:IHI0050H B2.10 Atomic transactions]
  //----------------------------------------------------------------------------

  function logic [511:0] chiAtomicApply(
    input chiReqFlitT req,
    input logic [511:0] priorValue,
    input logic [511:0] operand
  );
    int unsigned bytes;
    int unsigned bitOff;
    int unsigned width;
    logic [511:0] result;
    logic [63:0] oldVal;
    logic [63:0] newVal;
    logic [63:0] arg;
    logic [63:0] swapVal;

    result = priorValue;
    bytes = datTransferBytes(req.size);
    // AtomicCompare carries compare and swap values back to back, so its
    // operand is twice the data width; the others carry one value.
    width = (req.opcode == REQ_ATOMIC_COMPARE) ? (bytes * 8) / 2 : bytes * 8;
    if (width > 64)
      width = 64;
    bitOff = int'(req.addr[5:0]) * 8;

    oldVal = '0;
    arg = '0;
    for (int unsigned b = 0; b < width; b++) begin
      oldVal[b] = priorValue[bitOff + b];
      arg[b] = operand[bitOff + b];
    end

    case (req.opcode)
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_LOAD_ADD: newVal = oldVal + arg;
      REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_LOAD_CLR: newVal = oldVal & ~arg;
      REQ_ATOMIC_STORE_EOR, REQ_ATOMIC_LOAD_EOR: newVal = oldVal ^ arg;
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_LOAD_SET: newVal = oldVal | arg;
      REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_LOAD_SMAX:
        newVal = chiSignedGt(oldVal, arg, width) ? oldVal : arg;
      REQ_ATOMIC_STORE_SMIN, REQ_ATOMIC_LOAD_SMIN:
        newVal = chiSignedGt(oldVal, arg, width) ? arg : oldVal;
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_LOAD_UMAX: newVal = (oldVal > arg) ? oldVal : arg;
      REQ_ATOMIC_STORE_UMIN, REQ_ATOMIC_LOAD_UMIN: newVal = (oldVal > arg) ? arg : oldVal;
      REQ_ATOMIC_SWAP: newVal = arg;
      REQ_ATOMIC_COMPARE: begin
        swapVal = '0;
        for (int unsigned b = 0; b < width; b++)
          swapVal[b] = operand[bitOff + width + b];
        newVal = (oldVal == arg) ? swapVal : oldVal;
      end
      default: newVal = oldVal;
    endcase

    for (int unsigned b = 0; b < width; b++)
      result[bitOff + b] = newVal[b];
    return result;
  endfunction

  // Sign extension by shifting, because the operand width is a run-time
  // value and a part select needs a constant one.
  function bit chiSignedGt(input logic [63:0] a, input logic [63:0] b, input int unsigned width);
    logic signed [63:0] sa;
    logic signed [63:0] sb;
    int unsigned shift;
    shift = 64 - width;
    sa = signed'(a) <<< shift;
    sb = signed'(b) <<< shift;
    return (sa >>> shift) > (sb >>> shift);
  endfunction

  //----------------------------------------------------------------------------
  // Flit construction and bookkeeping
  //----------------------------------------------------------------------------

  function chiRspFlitT chiBlankRsp();
    chiRspFlitT flit;
    flit = '{default: '0, opcode: RSP_LCRD_RETURN};
    return flit;
  endfunction

  function chiDatFlitT chiBlankDat();
    chiDatFlitT flit;
    flit = '{default: '0, opcode: DAT_LCRD_RETURN};
    return flit;
  endfunction

  task automatic chiSendSimpleRsp(
    input chiReqFlitT req,
    input chiRspOpcodeE opcode,
    input chiRespErrE err,
    input chiTxnIdT dbId
  );
    chiRspFlitT rsp;
    rsp = chiBlankRsp();
    rsp.qos = req.qos;
    rsp.tgtId = req.srcId;
    rsp.txnId = req.txnId;
    rsp.opcode = opcode;
    rsp.respErr = err;
    rsp.dbId = dbId;
    rsp.traceTag = req.traceTag;
    if (cov != null)
      cov.sampleResponse(opcode, err, cfg.combinedWriteResp);
    bfm.driveRsp(rsp);
  endtask

  task automatic chiSendData(
    input chiReqFlitT req,
    input chiDatOpcodeE opcode,
    input logic [511:0] value,
    input int unsigned beat,
    input int unsigned beats,
    input chiRespErrE err
  );
    chiDatFlitT flit;
    int unsigned bitOff;
    flit = chiBlankDat();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.homeNid = req.srcId;
    flit.txnId = req.txnId;
    flit.opcode = opcode;
    flit.respErr = err;
    // Data from memory is not held in any cache, so the state the Home ends
    // up in is UC. [SPEC:IHI0050H B13.10.46 Table B13.35]
    flit.resp = RESP_UC_UD;
    flit.dataId = datDataId(req.addr, beat);
    flit.dbId = req.txnId;
    flit.traceTag = req.traceTag;
    flit.be = {BE_W{1'b1}};
    bitOff = int'(flit.dataId) * 128;
    flit.data = value[bitOff +: DATA_W];
    if (POISON_EN)
      flit.poison = '0;
    // NumDat stays zero: this model never elides packets, so Size alone says
    // how many arrive. See OPEN QUESTIONS Q8.
    flit.numDat = '0;
    bfm.driveDat(flit);
  endtask

  task automatic chiWaitResponse(input chiSubordinateTx rule);
    int unsigned delay;
    int unsigned extra;
    extra = (rule != null) ? rule.extraDelay : 0;
    if (cfg.maxRespDelay > cfg.minRespDelay)
      delay = cfg.minRespDelay + ($urandom % (cfg.maxRespDelay - cfg.minRespDelay + 1));
    else
      delay = cfg.minRespDelay;
    delay = delay + extra;
    if (delay > 0)
      bfm.waitClocks(delay);
  endtask

  task automatic chiAllocDbId(input chiSubordinateTxnContext ctx);
    forever begin
      dbIdGuard.get(1);
      if (freeDbId.size() > 0) begin
        ctx.dbId = freeDbId.pop_front();
        ctxByDbId[ctx.dbId] = ctx;
        dbIdGuard.put(1);
        return;
      end
      dbIdGuard.put(1);
      bfm.waitClocks(1);
    end
  endtask

  task automatic chiFreeDbId(input chiSubordinateTxnContext ctx);
    dbIdGuard.get(1);
    ctxByDbId.delete(ctx.dbId);
    freeDbId.push_back(ctx.dbId);
    dbIdGuard.put(1);
  endtask

  task automatic chiLockLine(input chiAddrT line);
    semaphore sem;
    lineGuard.get(1);
    if (!lineLock.exists(line))
      lineLock[line] = new(1);
    sem = lineLock[line];
    lineGuard.put(1);
    sem.get(1);
  endtask

  task automatic chiUnlockLine(input chiAddrT line);
    lineLock[line].put(1);
  endtask
endclass
