// Pin traffic for one requester. Four threads share the work:
// mainLoop accepts intent, workers issue it, rspRouter and datRouter
// demultiplex completions, and snoopHandler answers snoops. The cache
// lock is held only around the cache read or update, so a snoop is not
// stuck behind a round trip. Every pin touch is a BFM task.
// [TOP:reqToNoc] [ASSUMPTION:4] [ASSUMPTION:9] [ASSUMPTION:13] [ASSUMPTION:14]

class chiRequesterDriverProxy extends uvm_driver#(chiRequesterTx);
  virtual chiRequesterDriverBfm bfm;
  chiRequesterConfig cfg;
  chiRequesterCacheModel cache;
  chiRequesterCoverage cov;

  semaphore outstandingSlots;
  semaphore txnGuard;
  semaphore pcrdGuard;
  semaphore lineGuard;
  mailbox #(chiRequesterTx) launchMb;
  chiTxnIdT freeTxnId[$];
  int unsigned pcrdCount[chiPcrdKeyT];
  event pcrdEvent;
  semaphore lineLock[chiAddrT];
  chiRequesterTxnContext txnById[chiTxnIdT];
  bit dvmFirst[chiTxnIdT];
  bit sysCoOn;

  `uvm_component_utils(chiRequesterDriverProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    sysCoOn = 1'b0;
  endfunction

  function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);
    if (!uvm_config_db#(chiRequesterConfig)::get(this, "", "chiRequesterConfig", cfg))
      `uvm_fatal("chiRequesterConfig", "config_db get failed for key chiRequesterConfig")
    cfg.chiNormalize();
    key = cfg.driverKey();
    if (!uvm_config_db#(virtual chiRequesterDriverBfm)::get(this, "", key, bfm))
      `uvm_fatal("chiRequesterDriverProxy", {"config_db get failed for key ", key})
    cache = chiRequesterCacheModel::type_id::create("cache");
    outstandingSlots = new(cfg.outstandingCap);
    txnGuard = new(1);
    pcrdGuard = new(1);
    lineGuard = new(1);
    launchMb = new();
    for (int unsigned id = 0; id < cfg.outstandingCap; id++)
      freeTxnId.push_back(chiTxnIdT'(id));
  endfunction

  task run_phase(uvm_phase phase);
    bfm.waitConfigured();
    bfm.linkInit();
    bfm.linkStart();
    bfm.linkActivate();
    if (cfg.useSysCo && nodeClassUsesSysCo(cfg.nodeClass)) begin
      bfm.sysCoEnter();
      sysCoOn = 1'b1;
    end
    fork
      mainLoop();
      rspRouter();
      datRouter();
      snoopHandler();
    join_none
    for (int unsigned worker = 0; worker < cfg.outstandingCap; worker++) begin
      fork
        begin
          automatic int unsigned workerId = worker;
          chiWorker(workerId);
        end
      join_none
    end
  endtask

  task shutdown_phase(uvm_phase phase);
    if (sysCoOn) begin
      bfm.sysCoExit();
      sysCoOn = 1'b0;
    end
    bfm.linkDeactivate();
  endtask

  task automatic mainLoop();
    forever begin
      chiRequesterTx item;
      chiRequesterTx snapshot;
      seq_item_port.get_next_item(item);
      outstandingSlots.get(1);
      snapshot = chiRequesterTx::type_id::create("snapshot");
      snapshot.chiCopyFrom(item);
      snapshot.nodeClass = cfg.nodeClass;
      snapshot.set_id_info(item);
      launchMb.put(snapshot);
      seq_item_port.item_done();
    end
  endtask

  task automatic chiWorker(input int unsigned workerId);
    chiRequesterTx item;
    if (workerId >= cfg.outstandingCap)
      return;
    forever begin
      launchMb.get(item);
      chiCompleteItem(item);
      outstandingSlots.put(1);
    end
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

  task automatic chiAllocTxnId(output chiTxnIdT txnId);
    txnGuard.get(1);
    if (freeTxnId.size() == 0) begin
      txnGuard.put(1);
      `uvm_fatal("chiRequesterDriverProxy", "TxnID pool empty")
    end
    txnId = freeTxnId.pop_front();
    txnGuard.put(1);
  endtask

  task automatic chiFreeTxnId(input chiTxnIdT txnId);
    txnGuard.get(1);
    freeTxnId.push_back(txnId);
    txnById.delete(txnId);
    txnGuard.put(1);
  endtask

  task automatic chiTakePcrd(
    input chiNodeIdT srcId,
    input logic [P_CRD_TYPE_W-1:0] pcrdType
  );
    chiPcrdKeyT key;
    key.srcId = srcId;
    key.pcrdType = pcrdType;
    forever begin
      pcrdGuard.get(1);
      if (pcrdCount.exists(key) && (pcrdCount[key] > 0)) begin
        pcrdCount[key]--;
        pcrdGuard.put(1);
        return;
      end
      pcrdGuard.put(1);
      @pcrdEvent;
    end
  endtask

  function chiReqFlitT chiBlankReq();
    chiReqFlitT flit;
    flit = '{default: '0, opcode: REQ_LCRD_RETURN};
    return flit;
  endfunction

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

  task automatic chiSendRequest(
    input chiRequesterTx item,
    input chiReqOpcodeE opcode,
    input chiTxnIdT txnId,
    input bit allowRetry,
    input chiNodeIdT tgtId
  );
    chiReqFlitT flit;
    flit = chiBlankReq();
    flit.qos = item.qos;
    flit.tgtId = tgtId;
    flit.srcId = cfg.nodeId;
    flit.txnId = txnId;
    flit.opcode = opcode;
    flit.size = item.size;
    // MultiReq 0 is what selects the Size reading of the shared slot. The DUT
    // has no MultiReq logic at all (finding F-4), so it is never driven 1.
    flit.multiReq = 1'b0;
    flit.numReq = '0;
    flit.addr = item.addr;
    flit.pas = item.pas;
    flit.allowRetry = allowRetry;
    flit.order = item.order;
    flit.pCrdType = item.pCrdType;
    flit.memAttr = item.memAttr;
    flit.snpAttr = item.snpAttr;
    flit.sharedSlot = reqSlotLpId(item.sharedSlot);
    flit.excl = item.excl;
    flit.expCompAck = item.expCompAck;
    // [TOP:reqToNoc] AllowRetry 0 keeps the TgtID this requester drives.
    bfm.sendReqFlit(packReq(flit));
  endtask

  task automatic chiCompleteItem(input chiRequesterTx item);
    chiCacheStateE state;
    chiReqOpcodeE opcode;
    bit localOnly;
    chiAddrT line;
    chiTxnIdT txnId;
    chiRequesterTxnContext ctx;
    int wake;
    line = cache.chiLineAddr(item.addr);
    chiLockLine(line);
    state = cache.chiLookup(item.addr);
    cache.chiPickOpcode(item, state, opcode, localOnly);
    item.initialState = state;
    item.issuedOpcode = opcode;
    item.localOnly = localOnly;
    if (localOnly)
      cache.chiApplyLocal(item.intent, item.addr);
    chiUnlockLine(line);
    if (cov != null)
      cov.sampleIssue(item);
    if (localOnly) begin
      seq_item_port.put_response(item);
      return;
    end
    if (opcode == REQ_P_CRD_RETURN)
      chiTakePcrd(item.tgtId, item.pCrdType);
    chiAllocTxnId(txnId);
    ctx = new();
    ctx.item = item;
    ctx.txnId = txnId;
    ctx.opcode = opcode;
    if (cache.chiExpectsReadData(opcode))
      ctx.beatsLeft = datPacketCount(item.size);
    txnGuard.get(1);
    txnById[txnId] = ctx;
    txnGuard.put(1);
    chiSendRequest(item, opcode, txnId, item.allowRetry, item.tgtId);
    forever begin
      ctx.ping.get(wake);
      if (ctx.retrySeen && !ctx.retrySent) begin
        chiTakePcrd(ctx.homeId, ctx.pcrdType);
        item.pCrdType = ctx.pcrdType;
        chiSendRequest(item, opcode, txnId, 1'b0, ctx.homeId);
        ctx.retrySent = 1'b1;
        ctx.retrySeen = 1'b0;
      end
      if (ctx.gotDbid && !ctx.dataSent && cache.chiExpectsWriteData(opcode)) begin
        chiSendWriteData(ctx);
        ctx.dataSent = 1'b1;
      end
      if (item.intent == CHI_INTENT_DVM_OP && ctx.gotDbid && !ctx.dataSent) begin
        chiSendDvmData(ctx);
        ctx.dataSent = 1'b1;
      end
      if (ctx.gotResp && (ctx.beatsLeft == 0) && !ctx.retrySeen
          && (!cache.chiExpectsWriteData(opcode) || ctx.dataSent)
          && (item.intent != CHI_INTENT_DVM_OP || !cfg.expectDvmDbidResp || ctx.dataSent))
        break;
    end
    if (item.expCompAck)
      chiSendCompAck(ctx);
    chiLockLine(line);
    cache.chiNoteComp(item.addr, opcode, ctx.compResp, ctx.data);
    chiUnlockLine(line);
    chiFreeTxnId(txnId);
    seq_item_port.put_response(item);
  endtask

  task automatic chiSendWriteData(input chiRequesterTxnContext ctx);
    int unsigned beats;
    int unsigned beat;
    chiDatFlitT flit;
    beats = datPacketCount(ctx.item.size);
    for (beat = 0; beat < beats; beat++) begin
      flit = chiBlankDat();
      flit.tgtId = ctx.homeId;
      flit.srcId = cfg.nodeId;
      flit.homeNid = ctx.homeId;
      flit.txnId = ctx.dbId;
      flit.opcode = cache.chiIsCopyBack(ctx.opcode)
        ? DAT_COPY_BACK_WR_DATA : DAT_NON_COPY_BACK_WR_DATA;
      flit.dataId = datDataId(ctx.item.addr, beat);
      flit.respErr = RESP_ERR_OK;
      if (ctx.item.size == SIZE_W'(6))
        flit.be = {BE_W{1'b1}};
      else
        flit.be = ctx.item.be[BE_W-1:0];
      flit.data = ctx.item.data[beat * DATA_W +: DATA_W];
      bfm.sendDatFlit(packDat(flit));
    end
  endtask

  task automatic chiSendDvmData(input chiRequesterTxnContext ctx);
    chiDatFlitT flit;
    flit = chiBlankDat();
    flit.tgtId = ctx.homeId;
    flit.srcId = cfg.nodeId;
    flit.homeNid = ctx.homeId;
    flit.txnId = ctx.dbId;
    flit.opcode = DAT_NON_COPY_BACK_WR_DATA;
    flit.dataId = '0;
    flit.respErr = RESP_ERR_OK;
    flit.be = '0;
    flit.be[7:0] = 8'hff;
    flit.data = ctx.item.data[DATA_W-1:0];
    bfm.sendDatFlit(packDat(flit));
    if (cfg.expectDvmDbidResp == 1'b0)
      `uvm_warning("chiRequesterDriverProxy", "DVM DBIDResp arrived; F-6 expects it to be absent")
  endtask

  task automatic chiSendCompAck(input chiRequesterTxnContext ctx);
    chiRspFlitT flit;
    flit = chiBlankRsp();
    flit.tgtId = ctx.homeId;
    flit.srcId = cfg.nodeId;
    flit.txnId = ctx.dbId;
    flit.opcode = RSP_COMP_ACK;
    flit.respErr = RESP_ERR_OK;
    bfm.sendRspFlit(packRsp(flit));
  endtask

  task automatic rspRouter();
    chiRawFlitT raw;
    chiRspFlitT flit;
    forever begin
      bfm.getRspFlit(raw);
      if (isLcrdReturn(CHI_CH_RSP, raw))
        continue;
      flit = unpackRsp(raw);
      if (flit.opcode == RSP_P_CRD_GRANT) begin
        chiPcrdKeyT key;
        key.srcId = flit.srcId;
        key.pcrdType = flit.pCrdType;
        pcrdGuard.get(1);
        if (!pcrdCount.exists(key))
          pcrdCount[key] = 0;
        pcrdCount[key]++;
        pcrdGuard.put(1);
        -> pcrdEvent;
        continue;
      end
      begin
        chiRequesterTxnContext ctx;
        bit found;
        txnGuard.get(1);
        found = txnById.exists(flit.txnId);
        if (found)
          ctx = txnById[flit.txnId];
        txnGuard.put(1);
        if (!found) begin
          `uvm_error("chiRequesterDriverProxy",
            {$sformatf("RSP txnId %0h opcode %s has no requester", flit.txnId, flit.opcode.name())})
          continue;
        end
        chiNoteRsp(ctx, flit);
        ctx.ping.put(1);
      end
    end
  endtask

  function void chiNoteRsp(chiRequesterTxnContext ctx, chiRspFlitT flit);
    ctx.homeId = flit.srcId;
    if (flit.opcode == RSP_RETRY_ACK) begin
      ctx.retrySeen = 1'b1;
      ctx.pcrdType = flit.pCrdType;
      ctx.gotResp = 1'b0;
      return;
    end
    if (flit.opcode == RSP_DBID_RESP || flit.opcode == RSP_DBID_RESP_ORD
        || flit.opcode == RSP_COMP_DBID_RESP) begin
      ctx.gotDbid = 1'b1;
      ctx.dbId = flit.dbId;
    end
    if (flit.opcode == RSP_COMP || flit.opcode == RSP_COMP_DBID_RESP
        || flit.opcode == RSP_COMP_CMO || flit.opcode == RSP_RESP_SEP_DATA) begin
      ctx.gotResp = 1'b1;
      ctx.compResp = flit.resp;
    end
    if (ctx.item.intent == CHI_INTENT_DVM_OP && ctx.gotResp && !ctx.gotDbid
        && cfg.expectDvmDbidResp)
      `uvm_error("chiRequesterDriverProxy", "DVM Comp without DBIDResp while expectDvmDbidResp is set")
  endfunction

  task automatic datRouter();
    chiRawFlitT raw;
    chiDatFlitT flit;
    forever begin
      bfm.getDatFlit(raw);
      if (isLcrdReturn(CHI_CH_DAT, raw))
        continue;
      flit = unpackDat(raw);
      begin
        chiRequesterTxnContext ctx;
        bit found;
        txnGuard.get(1);
        found = txnById.exists(flit.txnId);
        if (found)
          ctx = txnById[flit.txnId];
        txnGuard.put(1);
        if (!found) begin
          `uvm_error("chiRequesterDriverProxy",
            {$sformatf("DAT txnId %0h opcode %s has no requester", flit.txnId, flit.opcode.name())})
          continue;
        end
        chiNoteDat(ctx, flit);
        ctx.ping.put(1);
      end
    end
  endtask

  function void chiNoteDat(chiRequesterTxnContext ctx, chiDatFlitT flit);
    int unsigned shift;
    ctx.homeId = flit.srcId;
    if (ctx.beatsLeft > 0)
      ctx.beatsLeft--;
    shift = int'(flit.dataId) * 128;
    begin
      logic [511:0] wide;
      wide = '0;
      wide[DATA_W-1:0] = flit.data;
      ctx.data = ctx.data | (wide << shift);
    end
    if (flit.opcode == DAT_COMP_DATA || flit.opcode == DAT_DATA_SEP_RESP) begin
      ctx.gotResp = 1'b1;
      ctx.compResp = flit.resp;
      ctx.dbId = flit.dbId;
    end
  endfunction

  task automatic snoopHandler();
    chiRawFlitT raw;
    chiSnpFlitT snp;
    forever begin
      bfm.getSnpFlit(raw);
      if (isLcrdReturn(CHI_CH_SNP, raw))
        continue;
      snp = unpackSnp(raw);
      if (cfg.nodeClass == RN_F && !sysCoOn)
        `uvm_error("chiRequesterDriverProxy", "snoop arrived before SYSCOREQ")
      if (snp.opcode == SNP_DVM_OP)
        chiHandleDvm(snp);
      else
        chiHandleCoherentSnoop(snp);
    end
  endtask

  task automatic chiHandleDvm(input chiSnpFlitT snp);
    if (cfg.nodeClass == RN_I) begin
      if (cfg.allowRniDvmSnoop)
        `uvm_warning("chiRequesterDriverProxy", "RN-I received SnpDVMOp (F-5)")
      else
        `uvm_error("chiRequesterDriverProxy", "RN-I received SnpDVMOp and allowRniDvmSnoop is 0")
    end
    if (!dvmFirst.exists(snp.txnId)) begin
      dvmFirst[snp.txnId] = 1'b1;
      return;
    end
    dvmFirst.delete(snp.txnId);
    chiSendSnpResp(snp, RESP_I, 1'b0, '0);
  endtask

  task automatic chiHandleCoherentSnoop(input chiSnpFlitT snp);
    chiAddrT line;
    chiCacheStateE stateBefore;
    chiCacheStateE finalState;
    logic [RESP_W-1:0] resp;
    bit withData;
    logic [511:0] data;
    if (cfg.nodeClass != RN_F) begin
      `uvm_error("chiRequesterDriverProxy",
        {$sformatf("coherent snoop %s on %s", snp.opcode.name(), nodeClassName(cfg.nodeClass))})
      chiSendSnpResp(snp, RESP_I, 1'b0, '0);
      return;
    end
    line = cache.chiLineAddr(snp.addr);
    chiLockLine(line);
    stateBefore = cache.chiLookup(snp.addr);
    cache.chiPlanSnoop(snp.addr, snp.opcode, snp.retToSrc,
      finalState, resp, withData, data);
    chiUnlockLine(line);
    if (cov != null)
      cov.sampleSnoop(snp.opcode, stateBefore);
    chiSendSnpResp(snp, resp, withData, data);
  endtask

  task automatic chiSendSnpResp(
    input chiSnpFlitT snp,
    input logic [RESP_W-1:0] resp,
    input bit withData,
    input logic [511:0] data
  );
    chiRspFlitT rsp;
    int unsigned beat;
    int unsigned beats;
    rsp = chiBlankRsp();
    rsp.tgtId = snp.srcId;
    rsp.srcId = cfg.nodeId;
    rsp.txnId = snp.txnId;
    rsp.opcode = RSP_SNP_RESP;
    rsp.resp = resp;
    rsp.respErr = RESP_ERR_OK;
    bfm.sendRspFlit(packRsp(rsp));
    if (!withData)
      return;
    beats = datPacketCount(SIZE_W'(6));
    for (beat = 0; beat < beats; beat++) begin
      chiDatFlitT flit;
      flit = chiBlankDat();
      flit.tgtId = snp.srcId;
      flit.srcId = cfg.nodeId;
      flit.txnId = snp.txnId;
      flit.opcode = DAT_SNP_RESP_DATA;
      flit.resp = resp;
      flit.respErr = RESP_ERR_OK;
      flit.dataId = datDataId(snp.addr, beat);
      flit.be = {BE_W{1'b1}};
      flit.data = data[beat * DATA_W +: DATA_W];
      bfm.sendDatFlit(packDat(flit));
    end
  endtask
endclass
