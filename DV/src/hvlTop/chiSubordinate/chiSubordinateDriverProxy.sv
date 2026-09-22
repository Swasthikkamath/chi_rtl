// Answers REQ on one SN-F or SN-I port. policyLoop applies sequence
// items to the config. reqLoop, datRouter and rspRouter move flits.
// A blocked sequencer does not stall requests. Every pin touch is a
// BFM task. HomeNID is left at 0: this agent does not guess a home.
// SYSCO is not entered.
// [TOP:reqToNoc] [ASSUMPTION:4] [ASSUMPTION:7] [ASSUMPTION:8]
// [ASSUMPTION:9] [ASSUMPTION:10] [ASSUMPTION:15] [SPEC:IHI0050H B4.2]
// [SPEC:IHI0050H B13.8]

class chiSubordinateDriverProxy extends uvm_driver#(chiSubordinateTx);
  virtual chiSubordinateDriverBfm bfm;
  chiSubordinateConfig cfg;
  chiSubordinateMemoryModel mem;
  chiSubordinateCoverage cov;

  semaphore outstandingSlots;
  semaphore txnGuard;
  semaphore pcrdGuard;
  chiTxnIdT freeDbId[$];
  chiSubordinateTxnContext txnByDbId[chiTxnIdT];
  int unsigned pcrdCount[chiSubordinatePcrdKeyT];

  `uvm_component_utils(chiSubordinateDriverProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
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
    mem = chiSubordinateMemoryModel::type_id::create("mem");
    outstandingSlots = new(cfg.outstandingCap);
    txnGuard = new(1);
    pcrdGuard = new(1);
    for (int unsigned id = 0; id < cfg.outstandingCap; id++)
      freeDbId.push_back(chiTxnIdT'(id));
  endfunction

  task run_phase(uvm_phase phase);
    bfm.waitConfigured();
    bfm.linkInit();
    bfm.linkStart();
    bfm.linkActivate();
    fork
      policyLoop();
      reqLoop();
      datRouter();
      rspRouter();
    join
  endtask

  task shutdown_phase(uvm_phase phase);
    bfm.linkDeactivate();
  endtask

  task automatic policyLoop();
    forever begin
      chiSubordinateTx item;
      seq_item_port.get_next_item(item);
      cfg.enableRetry = item.enableRetry;
      cfg.injectRespErr = item.injectRespErr;
      seq_item_port.item_done();
    end
  endtask

  task automatic reqLoop();
    forever begin
      chiReqFlitT req;
      chiRawFlitT raw;
      bfm.getReq(req, raw);
      if (isLcrdReturn(CHI_CH_REQ, raw))
        continue;
      outstandingSlots.get(1);
      fork
        begin
          automatic chiReqFlitT reqLocal = req;
          chiServe(reqLocal);
          outstandingSlots.put(1);
        end
      join_none
    end
  endtask

  task automatic datRouter();
    forever begin
      chiDatFlitT flit;
      chiRawFlitT raw;
      chiSubordinateTxnContext ctx;
      bit found;
      bfm.getDat(flit, raw);
      if (isLcrdReturn(CHI_CH_DAT, raw))
        continue;
      txnGuard.get(1);
      found = txnByDbId.exists(flit.txnId);
      if (found)
        ctx = txnByDbId[flit.txnId];
      txnGuard.put(1);
      if (!found) begin
        `uvm_error("chiSubordinateDriverProxy",
          {$sformatf("DAT txnId %0h opcode %s has no subordinate", flit.txnId, flit.opcode.name())})
        continue;
      end
      ctx.datMb.put(flit);
    end
  endtask

  task automatic rspRouter();
    forever begin
      chiRspFlitT flit;
      chiRawFlitT raw;
      chiSubordinateTxnContext ctx;
      bit found;
      bfm.getRsp(flit, raw);
      if (isLcrdReturn(CHI_CH_RSP, raw))
        continue;
      if (flit.opcode != RSP_COMP_ACK) begin
        `uvm_error("chiSubordinateDriverProxy",
          {$sformatf("RSP txnId %0h opcode %s is not CompAck", flit.txnId, flit.opcode.name())})
        continue;
      end
      txnGuard.get(1);
      found = txnByDbId.exists(flit.txnId);
      if (found)
        ctx = txnByDbId[flit.txnId];
      txnGuard.put(1);
      if (!found) begin
        `uvm_error("chiSubordinateDriverProxy",
          {$sformatf("CompAck txnId %0h has no subordinate", flit.txnId)})
        continue;
      end
      ctx.ackMb.put(flit);
    end
  endtask

  function void chiSample(input chiReqOpcodeE opcode);
    if (cov == null)
      return;
    if (chiOpcodeIsAtomic(opcode))
      cov.sampleAtomic(opcode);
    else
      cov.sampleIssue(opcode, cfg.nodeClass);
  endfunction

  function bit chiOpcodeIsAtomic(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN,
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiAtomicReturnsData(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  // Same opcodes the requester waits on, so an illegal request is still
  // completed and the link does not stall.
  function bit chiNeedsWriteData(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_WRITE_BACK_FULL, REQ_WRITE_CLEAN_FULL,
      REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL,
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN,
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiNeedsReadData(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_ONCE,
      REQ_READ_NO_SNP, REQ_READ_UNIQUE,
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiLegalOpcode(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_READ_NO_SNP, REQ_READ_NO_SNP_SEP,
      REQ_READ_ONCE, REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID,
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL, REQ_WRITE_NO_SNP_ZERO,
      REQ_P_CRD_RETURN,
      REQ_CLEAN_SHARED, REQ_CLEAN_INVALID, REQ_MAKE_INVALID,
      REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP:
        return 1'b1;
      REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_ZERO,
      REQ_PREFETCH_TGT:
        return (cfg.nodeClass == SN_F);
      default: return 1'b0;
    endcase
  endfunction

  function int unsigned chiInboundPackets(
    input chiReqOpcodeE opcode,
    input logic [SIZE_W-1:0] size
  );
    int unsigned bytes;
    bytes = datTransferBytes(size);
    if (opcode == REQ_ATOMIC_COMPARE)
      bytes = bytes * 2;
    if (bytes <= DAT_BYTES_PER_PACKET)
      return 1;
    return (bytes + DAT_BYTES_PER_PACKET - 1) / DAT_BYTES_PER_PACKET;
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

  task automatic chiAllocContext(
    input chiReqFlitT req,
    output chiSubordinateTxnContext ctx
  );
    chiTxnIdT dbId;
    txnGuard.get(1);
    if (freeDbId.size() == 0) begin
      txnGuard.put(1);
      `uvm_fatal("chiSubordinateDriverProxy", "DBID pool empty")
    end
    dbId = freeDbId.pop_front();
    ctx = new();
    ctx.req = req;
    ctx.dbId = dbId;
    txnByDbId[dbId] = ctx;
    txnGuard.put(1);
  endtask

  task automatic chiFreeDbId(input chiTxnIdT dbId);
    txnGuard.get(1);
    txnByDbId.delete(dbId);
    freeDbId.push_back(dbId);
    txnGuard.put(1);
  endtask

  task automatic chiConsumeCredit(input chiReqFlitT req, input bit quiet);
    chiSubordinatePcrdKeyT key;
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
    if (missing && !quiet)
      `uvm_warning("chiSubordinateDriverProxy",
        {$sformatf("AllowRetry is 0 from src %0h pCrdType %0h and no P-credit is tracked",
          req.srcId, req.pCrdType)})
  endtask

  task automatic chiSendRetry(input chiReqFlitT req);
    chiRspFlitT flit;
    chiSubordinatePcrdKeyT key;
    flit = chiBlankRsp();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.srcId = cfg.nodeId;
    flit.txnId = req.txnId;
    flit.opcode = RSP_RETRY_ACK;
    flit.respErr = RESP_ERR_OK;
    flit.pCrdType = req.pCrdType;
    flit.traceTag = req.traceTag;
    bfm.driveRsp(flit);
    flit = chiBlankRsp();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.srcId = cfg.nodeId;
    flit.txnId = req.txnId;
    flit.opcode = RSP_P_CRD_GRANT;
    flit.respErr = RESP_ERR_OK;
    flit.pCrdType = req.pCrdType;
    flit.traceTag = req.traceTag;
    bfm.driveRsp(flit);
    key.srcId = req.srcId;
    key.pcrdType = req.pCrdType;
    pcrdGuard.get(1);
    if (!pcrdCount.exists(key))
      pcrdCount[key] = 0;
    pcrdCount[key]++;
    pcrdGuard.put(1);
  endtask

  task automatic chiSendRsp(
    input chiReqFlitT req,
    input chiRspOpcodeE opcode,
    input chiTxnIdT dbId,
    input chiRespErrE respErr
  );
    chiRspFlitT flit;
    flit = chiBlankRsp();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.srcId = cfg.nodeId;
    flit.txnId = req.txnId;
    flit.opcode = opcode;
    flit.dbId = dbId;
    flit.resp = RESP_I;
    flit.respErr = respErr;
    flit.traceTag = req.traceTag;
    bfm.driveRsp(flit);
  endtask

  function logic [511:0] chiImageFromMem(input chiReqFlitT req);
    logic [511:0] image;
    int unsigned nbytes;
    chiAddrT line;
    image = '0;
    nbytes = datTransferBytes(req.size);
    line = lineAlign(req.addr);
    for (int unsigned i = 0; i < CACHE_LINE_BYTES; i++)
      if (((line + i) >= req.addr) && ((line + i) < (req.addr + nbytes)))
        image[(i * 8) +: 8] = mem.chiByteAt(line + i);
    return image;
  endfunction

  function logic [511:0] chiValueImage(
    input chiAddrT addr,
    input logic [63:0] value,
    input int unsigned nbytes
  );
    logic [511:0] image;
    int unsigned offset;
    int unsigned count;
    image = '0;
    offset = int'(addr % CACHE_LINE_BYTES);
    count = nbytes;
    if (count > 8)
      count = 8;
    for (int unsigned i = 0; i < count; i++)
      if ((offset + i) < CACHE_LINE_BYTES)
        image[((offset + i) * 8) +: 8] = value[(i * 8) +: 8];
    return image;
  endfunction

  function logic [127:0] chiGatherInbound(
    input chiSubordinateTxnContext ctx,
    input int unsigned nbytes
  );
    logic [127:0] value;
    int unsigned offset;
    int unsigned count;
    value = '0;
    offset = int'(ctx.req.addr % CACHE_LINE_BYTES);
    count = nbytes;
    if (count > 16)
      count = 16;
    for (int unsigned i = 0; i < count; i++)
      if ((offset + i) < CACHE_LINE_BYTES)
        value[(i * 8) +: 8] = ctx.data[((offset + i) * 8) +: 8];
    return value;
  endfunction

  task automatic chiSendDataBeat(
    input chiReqFlitT req,
    input chiDatOpcodeE opcode,
    input chiTxnIdT dbId,
    input int unsigned packet,
    input logic [511:0] image,
    input chiRespErrE respErr
  );
    chiDatFlitT flit;
    int unsigned nbytes;
    int unsigned start;
    int unsigned beatByte;
    chiAddrT line;
    flit = chiBlankDat();
    flit.qos = req.qos;
    flit.tgtId = req.srcId;
    flit.srcId = cfg.nodeId;
    flit.txnId = req.txnId;
    flit.homeNid = '0;
    flit.opcode = opcode;
    flit.dbId = dbId;
    flit.dataId = datDataId(req.addr, packet);
    flit.resp = RESP_I;
    flit.respErr = respErr;
    flit.traceTag = req.traceTag;
    nbytes = datTransferBytes(req.size);
    line = lineAlign(req.addr);
    start = int'(flit.dataId) * 16;
    for (int unsigned i = 0; i < DAT_BYTES_PER_PACKET; i++) begin
      beatByte = start + i;
      if (beatByte >= CACHE_LINE_BYTES)
        break;
      if (((line + beatByte) >= req.addr) && ((line + beatByte) < (req.addr + nbytes))) begin
        flit.be[i] = 1'b1;
        flit.data[(i * 8) +: 8] = image[(beatByte * 8) +: 8];
      end
    end
    bfm.driveDat(flit);
  endtask

  task automatic chiCollectData(input chiSubordinateTxnContext ctx, input int unsigned beats);
    int unsigned got;
    got = 0;
    ctx.beatsLeft = beats;
    while (got < beats) begin
      chiDatFlitT flit;
      int unsigned baseByte;
      ctx.datMb.get(flit);
      if (flit.opcode == DAT_WRITE_DATA_CANCEL) begin
        ctx.cancelled = 1'b1;
        return;
      end
      if (!(flit.opcode inside {
        DAT_NON_COPY_BACK_WR_DATA, DAT_NCB_WR_DATA_COMP_ACK, DAT_COPY_BACK_WR_DATA
      }))
        `uvm_error("chiSubordinateDriverProxy",
          {$sformatf("DAT opcode %s is not write data", flit.opcode.name())})
      if (flit.opcode == DAT_NCB_WR_DATA_COMP_ACK)
        ctx.compAckSeen = 1'b1;
      baseByte = int'(flit.dataId) * 16;
      for (int unsigned i = 0; i < DAT_BYTES_PER_PACKET; i++) begin
        if ((baseByte + i) >= CACHE_LINE_BYTES)
          break;
        ctx.data[((baseByte + i) * 8) +: 8] = flit.data[(i * 8) +: 8];
        ctx.be[baseByte + i] = flit.be[i];
      end
      got++;
    end
  endtask

  task automatic chiWaitCompAck(input chiSubordinateTxnContext ctx);
    chiRspFlitT ack;
    if (!ctx.req.expCompAck)
      return;
    if (ctx.compAckSeen)
      return;
    ctx.ackMb.get(ack);
  endtask

  task automatic chiFinish(input chiSubordinateTxnContext ctx);
    chiWaitCompAck(ctx);
    chiFreeDbId(ctx.dbId);
  endtask

  task automatic chiCompleteRead(
    input chiReqFlitT req,
    input logic [511:0] image,
    input chiDatOpcodeE opcode,
    input bit separate,
    input chiRespErrE respErr
  );
    chiSubordinateTxnContext ctx;
    int unsigned beats;
    chiAllocContext(req, ctx);
    if (req.order != '0)
      chiSendRsp(req, RSP_READ_RECEIPT, ctx.dbId, RESP_ERR_OK);
    beats = datPacketCount(req.size);
    for (int unsigned packet = 0; packet < beats; packet++)
      chiSendDataBeat(req, opcode, ctx.dbId, packet, image, respErr);
    if (separate)
      chiSendRsp(req, RSP_RESP_SEP_DATA, ctx.dbId, respErr);
    chiFinish(ctx);
  endtask

  task automatic chiServeWrite(input chiReqFlitT req, input bit commit, input chiRespErrE respErr);
    chiSubordinateTxnContext ctx;
    chiRspOpcodeE compOpcode;
    chiAllocContext(req, ctx);
    chiSendRsp(req, RSP_DBID_RESP, ctx.dbId, respErr);
    chiCollectData(ctx, datPacketCount(req.size));
    if (commit && !ctx.cancelled)
      mem.chiMergeLine(lineAlign(req.addr), ctx.data, ctx.be);
    compOpcode = req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP;
    chiSendRsp(req, compOpcode, ctx.dbId, respErr);
    chiFinish(ctx);
  endtask

  task automatic chiServeZero(input chiReqFlitT req);
    chiSubordinateTxnContext ctx;
    chiRspOpcodeE compOpcode;
    chiAllocContext(req, ctx);
    mem.chiFillBytes(req.addr, datTransferBytes(req.size), 8'h00);
    compOpcode = req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP;
    chiSendRsp(req, compOpcode, ctx.dbId, cfg.injectRespErr);
    chiFinish(ctx);
  endtask

  task automatic chiServeCompOnly(input chiReqFlitT req, input chiRespErrE respErr);
    chiSubordinateTxnContext ctx;
    chiRspOpcodeE compOpcode;
    chiAllocContext(req, ctx);
    compOpcode = req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP;
    chiSendRsp(req, compOpcode, ctx.dbId, respErr);
    chiFinish(ctx);
  endtask

  task automatic chiFailAtomic(input chiReqFlitT req);
    chiSubordinateTxnContext ctx;
    logic [511:0] image;
    chiAllocContext(req, ctx);
    if (chiNeedsWriteData(req.opcode)) begin
      chiSendRsp(req, RSP_DBID_RESP, ctx.dbId, RESP_ERR_NDERR);
      chiCollectData(ctx, chiInboundPackets(req.opcode, req.size));
    end
    if (chiAtomicReturnsData(req.opcode)) begin
      image = '0;
      chiSendDataBeat(req, DAT_COMP_DATA, ctx.dbId, 0, image, RESP_ERR_NDERR);
    end else begin
      chiSendRsp(req, req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP, ctx.dbId, RESP_ERR_NDERR);
    end
    chiFinish(ctx);
  endtask

  task automatic chiServeAtomic(input chiReqFlitT req);
    chiSubordinateTxnContext ctx;
    int unsigned nbytes;
    int unsigned inboundBytes;
    logic [127:0] inbound;
    logic [63:0] oldValue;
    logic [511:0] image;
    if (!CHI_CFG.atomicEn) begin
      `uvm_error("chiSubordinateDriverProxy",
        {$sformatf("%s arrived with atomicEn clear", req.opcode.name())})
      chiFailAtomic(req);
      return;
    end
    if (req.size > SIZE_W'(3)) begin
      `uvm_error("chiSubordinateDriverProxy",
        {$sformatf("atomic %s size %0d is wider than 8 bytes", req.opcode.name(), req.size)})
      chiFailAtomic(req);
      return;
    end
    chiAllocContext(req, ctx);
    chiSendRsp(req, RSP_DBID_RESP, ctx.dbId, cfg.injectRespErr);
    chiCollectData(ctx, chiInboundPackets(req.opcode, req.size));
    if (ctx.cancelled) begin
      chiSendRsp(req, req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP, ctx.dbId, RESP_ERR_NDERR);
      chiFinish(ctx);
      return;
    end
    nbytes = datTransferBytes(req.size);
    inboundBytes = (req.opcode == REQ_ATOMIC_COMPARE) ? (nbytes * 2) : nbytes;
    inbound = chiGatherInbound(ctx, inboundBytes);
    oldValue = mem.chiAtomic(req.opcode, req.addr, nbytes, inbound);
    if (chiAtomicReturnsData(req.opcode)) begin
      image = chiValueImage(req.addr, oldValue, nbytes);
      chiSendDataBeat(req, DAT_COMP_DATA, ctx.dbId, 0, image, cfg.injectRespErr);
    end else begin
      chiSendRsp(req, req.expCompAck ? RSP_COMP_DBID_RESP : RSP_COMP,
        ctx.dbId, cfg.injectRespErr);
    end
    chiFinish(ctx);
  endtask

  task automatic chiServeIllegal(input chiReqFlitT req);
    `uvm_error("chiSubordinateDriverProxy",
      {$sformatf("%s is not a %s opcode", req.opcode.name(), nodeClassName(cfg.nodeClass))})
    if (chiNeedsWriteData(req.opcode))
      chiServeWrite(req, 1'b0, RESP_ERR_NDERR);
    else if (chiNeedsReadData(req.opcode))
      chiCompleteRead(req, '0, DAT_COMP_DATA, 1'b0, RESP_ERR_NDERR);
    else
      chiServeCompOnly(req, RESP_ERR_NDERR);
  endtask

  task automatic chiServe(input chiReqFlitT req);
    if (req.opcode == REQ_P_CRD_RETURN) begin
      chiConsumeCredit(req, 1'b1);
      chiSample(req.opcode);
      return;
    end
    if (cfg.enableRetry && req.allowRetry) begin
      chiSendRetry(req);
      return;
    end
    if (!req.allowRetry)
      chiConsumeCredit(req, 1'b0);
    chiSample(req.opcode);
    if (chiOpcodeIsAtomic(req.opcode)) begin
      chiServeAtomic(req);
      return;
    end
    if (!chiLegalOpcode(req.opcode)) begin
      chiServeIllegal(req);
      return;
    end
    case (req.opcode)
      REQ_READ_NO_SNP, REQ_READ_ONCE,
      REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID:
        chiCompleteRead(req, chiImageFromMem(req), DAT_COMP_DATA, 1'b0, cfg.injectRespErr);
      REQ_READ_NO_SNP_SEP:
        chiCompleteRead(req, chiImageFromMem(req), DAT_DATA_SEP_RESP, 1'b1, cfg.injectRespErr);
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
      REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL:
        chiServeWrite(req, 1'b1, cfg.injectRespErr);
      REQ_WRITE_NO_SNP_ZERO, REQ_WRITE_UNIQUE_ZERO:
        chiServeZero(req);
      REQ_CLEAN_SHARED, REQ_CLEAN_INVALID, REQ_MAKE_INVALID,
      REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP,
      REQ_PREFETCH_TGT:
        chiServeCompOnly(req, cfg.injectRespErr);
      default:
        chiServeCompOnly(req, RESP_ERR_NDERR);
    endcase
  endtask
endclass
