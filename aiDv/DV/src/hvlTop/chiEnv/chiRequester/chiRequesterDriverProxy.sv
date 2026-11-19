// Requester protocol engine.
//
// The sequence says what it wants in terms of an access at an address; this
// class decides how to get it. That division is deliberate: which opcode
// realises a read or a write depends on what the cache already holds, and a
// sequence that tried to choose the opcode itself would have to duplicate the
// cache state to do it, and would be wrong whenever a snoop changed that state
// between generation and driving. Here the lookup happens at the moment of
// issue, which is where a real cache controller does it.
//
// Four things run concurrently:
//
//   mainLoop      takes items from the sequencer and starts a transaction
//   rspRouter     demultiplexes arriving responses onto the transaction
//                 waiting for them
//   datRouter     the same for data
//   snoopHandler  answers snoops without reference to any of the above
//
// The routers exist because responses to different transactions arrive
// interleaved and out of order; there is one RSP channel and many transactions
// in flight, so something has to sort them. The snoop handler is a separate
// thread rather than a branch of the main loop because a snoop can arrive
// while this Requester is itself blocked waiting for a completion, and the
// fabric can be waiting for the snoop response before it will produce that
// completion. Handling snoops only between transactions would deadlock exactly
// there.
class chiRequesterDriverProxy extends uvm_driver #(chiRequesterTx);

  chiRequesterAgentConfig       cfg;
  virtual chiRequesterDriverBfm bfm;
  chiRequesterCacheModel        cache;

  // Transactions allowed in flight at once, which is what decides whether the
  // Home Node ever runs out of resources and answers RetryAck.
  protected semaphore outstandingSem;

  // TxnID is unique only among the transactions of one source node
  // [SPEC:IHI0050H B2.3.2], so this pool covers this agent alone.
  protected bit txnIdBusy [chiTxnIdT];
  protected semaphore txnIdLock;

  // A cache keeps a line locked while it is being snooped, so a store cannot
  // land between the snoop reading the data out and the snoop changing the
  // state. Without that, the snooped data and the state this Requester keeps
  // describe different contents, and the peer given that data diverges from
  // this one. The lock covers the whole snoop, including the data beats.
  protected semaphore snoopLock;

  // A transaction in flight owns a mailbox per channel it expects to hear on,
  // and the routers post into them.
  protected mailbox #(chi_rsp_flit_t) rspMbox [chiTxnIdT];
  protected mailbox #(chi_dat_flit_t) datMbox [chiTxnIdT];

  // P-Credits granted but not yet spent, keyed by the Home Node that granted
  // them and the credit type. A grant carries no TxnID, so it cannot be
  // matched to the request it unblocks; it is a credit against a pool
  // [SPEC:IHI0050H B2.5.5, hnf/chi_hnf_top.sv grantFlit].
  protected int unsigned pCrdPool [string];

  protected int unsigned transactionsIssued;
  protected int unsigned retriesSeen;
  protected int unsigned snoopsAnswered;

  // Distinguishes one store from the next, so the bytes a store leaves behind
  // are unique to this agent and this store. Without that a write would leave
  // the line holding exactly what it already held, and no end-to-end data
  // check downstream could tell whether the fabric had moved the right bytes
  // or simply never moved any.
  protected int unsigned storeSerial;

  `uvm_component_utils(chiRequesterDriverProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    outstandingSem = new(cfg.maxOutstanding);
    txnIdLock      = new(1);
    snoopLock      = new(1);
  endfunction

  // -------------------------------------------------------------------------
  // Phases
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    bfm.bringUp();
    `uvm_info(get_type_name(),
              $sformatf("%s brought up: %s", cfg.nodeClass.name(),
                        cfg.convert2string()), UVM_LOW)
    fork
      rspRouter();
      datRouter();
      if (cfg.hasCache) snoopHandler();
      mainLoop();
    join
  endtask

  // -------------------------------------------------------------------------
  // TxnID allocation
  // -------------------------------------------------------------------------
  protected task allocateTxnId(output chiTxnIdT txnId);
    bit found;
    found = 1'b0;
    while (!found) begin
      txnIdLock.get(1);
      for (int unsigned candidate = 0; candidate < 64; candidate++) begin
        if (!txnIdBusy.exists(chiTxnIdT'(candidate))
            || !txnIdBusy[chiTxnIdT'(candidate)]) begin
          txnId                 = chiTxnIdT'(candidate);
          txnIdBusy[txnId]      = 1'b1;
          rspMbox[txnId]        = new();
          datMbox[txnId]        = new();
          found                 = 1'b1;
          break;
        end
      end
      txnIdLock.put(1);
      if (!found) bfm.waitCycles(1);
    end
  endtask

  protected function void freeTxnId(chiTxnIdT txnId);
    txnIdBusy[txnId] = 1'b0;
    if (rspMbox.exists(txnId)) rspMbox.delete(txnId);
    if (datMbox.exists(txnId)) datMbox.delete(txnId);
  endfunction

  // -------------------------------------------------------------------------
  // Routers
  // -------------------------------------------------------------------------
  protected task rspRouter();
    chi_rsp_flit_t rsp;
    forever begin
      bfm.getResponse(rsp);
      `uvm_info(get_type_name(),
                $sformatf({"RX RSP %s TxnID 0x%0h from 0x%0h resp %s dbid ",
                           "0x%0h pcrd %0h"},
                          rsp.opcode.name(), rsp.txnId, rsp.srcId,
                          rsp.resp.name(), rsp.dbIdOrGroupId, rsp.pCrdType),
                UVM_DEBUG)
      if (rsp.opcode == RSP_PCRD_GRANT) begin
        // A grant is not tied to a transaction, so it goes into the pool for
        // whichever retried request is waiting on that credit type.
        string key;
        key = pCrdKey(rsp.srcId, rsp.pCrdType);
        if (!pCrdPool.exists(key)) pCrdPool[key] = 0;
        pCrdPool[key]++;
        `uvm_info(get_type_name(),
                  $sformatf("PCrdGrant from 0x%0h type %0h, pool now %0d",
                            rsp.srcId, rsp.pCrdType, pCrdPool[key]), UVM_HIGH)
      end else if (rspMbox.exists(rsp.txnId)) begin
        rspMbox[rsp.txnId].put(rsp);
      end else begin
        `uvm_error(get_type_name(),
                   $sformatf("response for unknown TxnID 0x%0h: %s",
                             rsp.txnId, rsp.opcode.name()))
      end
    end
  endtask

  protected task datRouter();
    chi_dat_flit_t dat;
    forever begin
      bfm.getData(dat);
      `uvm_info(get_type_name(),
                $sformatf("RX DAT %s TxnID 0x%0h from 0x%0h resp %s dataId %0h",
                          dat.opcode.name(), dat.txnId, dat.srcId,
                          dat.resp.name(), dat.dataId), UVM_DEBUG)
      if (datMbox.exists(dat.txnId)) begin
        datMbox[dat.txnId].put(dat);
      end else begin
        `uvm_error(get_type_name(),
                   $sformatf("data for unknown TxnID 0x%0h: %s",
                             dat.txnId, dat.opcode.name()))
      end
    end
  endtask

  protected function string pCrdKey(chiNodeIdT srcId, logic [3:0] pCrdType);
    return $sformatf("%0h_%0h", srcId, pCrdType);
  endfunction

  // -------------------------------------------------------------------------
  // Main loop
  // -------------------------------------------------------------------------
  protected task mainLoop();
    chiRequesterTx item;
    forever begin
      seq_item_port.get_next_item(item);
      outstandingSem.get(1);
      // The item is handed back as soon as the transaction has been launched.
      // Holding it until completion would make every agent single-threaded and
      // the Home Node would never run short of resources, so the retry path
      // would never be reached.
      fork
        automatic chiRequesterTx launched = item;
        begin
          runAccess(launched);
          outstandingSem.put(1);
        end
      join_none
      #0;
      seq_item_port.item_done();
    end
  endtask

  // -------------------------------------------------------------------------
  // Access handling
  // -------------------------------------------------------------------------
  // What a read or a write turns into depends on the class of this Requester
  // and, for a caching one, on what it already holds.
  protected task runAccess(chiRequesterTx item);
    item.agentId   = cfg.agentId;
    item.nodeClass = cfg.nodeClass;

    if (!cfg.hasCache) begin
      runIoCoherentAccess(item);
      return;
    end

    // A second transaction to a line that already has one in flight is not
    // allowed [SPEC:IHI0050H B2.6.1], so this one waits for the first. The
    // claim is taken in the same step as the check: several access threads run
    // concurrently, and any wait between finding the line free and marking it
    // lets a second thread find it free too. Both would then go to the fabric,
    // and the one whose request is retried can be overtaken by the other,
    // which leaves it reading a line it has meanwhile acquired and dirtied.
    while (cache.isOutstanding(item.addr)) bfm.waitCycles(1);
    cache.markOutstanding(item.addr);

    case (item.accessKind)
      CHI_ACCESS_READ:        runCoherentRead(item);
      CHI_ACCESS_READ_UNIQUE: runCoherentWrite(item);
      CHI_ACCESS_WRITE:       runCoherentWrite(item);
      CHI_ACCESS_EVICT:       runEviction(item.addr, 1'b1);
      default:                runCoherentRead(item);
    endcase

    cache.clearOutstanding(item.addr);
  endtask

  // A read that hits on any valid state needs no transaction at all. This is
  // the whole reason the cache lookup belongs here: the decision not to go to
  // the fabric can only be made once, at issue, against current state.
  protected task runCoherentRead(chiRequesterTx item);
    chi_req_flit_t   req;
    chi_rsp_flit_t   rsp;
    chi_dat_flit_t   dat;
    chiTxnIdT        txnId;
    chiLineBytesT    lineBytes;

    if (cache.isValid(item.addr)) begin
      cache.touch(item.addr);
      item.completionResp = RESP_SC;
      item.completionErr  = RESP_ERR_OK;
      `uvm_info(get_type_name(),
                $sformatf("read hit on 0x%0h in state %s", item.addr,
                          cache.lookup(item.addr).name()), UVM_HIGH)
      return;
    end

    makeRoomIfNeeded();

    allocateTxnId(txnId);

    req = baseRequest(item, txnId);
    // ReadShared asks for a copy that may be shared with others, which is what
    // a load wants [SPEC:IHI0050H B2.3.1].
    req.opcode      = REQ_READ_SHARED;
    // The Home must be told when the Requester will acknowledge completion,
    // because it holds the transaction open until the CompAck arrives
    // [SPEC:IHI0050H B2.3.2].
    req.expCompAck  = 1'b1;

    issueWithRetry(req, txnId, item);

    collectReadData(txnId, item, rsp, dat, lineBytes);

    cache.writeLine(item.addr, lineBytes);
    cache.updateOnCompletion(item.addr, dat.resp);
    item.completionResp = dat.resp;
    item.completionErr  = dat.respErr;

    sendCompAck(txnId, dat.srcId, dat.dbId);
    freeTxnId(txnId);
  endtask

  // A store needs the line unique. Already unique means no transaction; shared
  // means an upgrade; absent means fetching it with intent to write.
  protected task runCoherentWrite(chiRequesterTx item);
    chi_req_flit_t req;
    chi_rsp_flit_t rsp;
    chi_dat_flit_t dat;
    chiTxnIdT      txnId;
    chiLineBytesT  lineBytes;

    // Already unique, so the store needs no transaction at all: this
    // Requester holds the only copy and may write it silently
    // [SPEC:IHI0050H B2.2].
    if (cache.isUnique(item.addr)) begin
      applyStore(item.addr);
      cache.touch(item.addr);
      item.completionResp = RESP_UC_UD;
      item.completionErr  = RESP_ERR_OK;
      return;
    end

    allocateTxnId(txnId);
    req = baseRequest(item, txnId);

    if (cache.isValid(item.addr)) begin
      // The line is here but shared. CleanUnique upgrades it without moving
      // data, because this Requester already has the data
      // [SPEC:IHI0050H B2.3.1].
      req.opcode     = REQ_CLEAN_UNIQUE;
      req.expCompAck = 1'b1;
      issueWithRetry(req, txnId, item);
      waitForResponse(txnId, rsp);
      if (rsp.opcode != RSP_COMP)
        `uvm_error(get_type_name(),
                   $sformatf("CleanUnique expected Comp, saw %s",
                             rsp.opcode.name()))
      cache.updateOnCompletion(item.addr, rsp.resp);
      item.completionResp = rsp.resp;
      item.completionErr  = rsp.respErr;
      sendCompAck(txnId, rsp.srcId, rsp.dbIdOrGroupId);
    end else begin
      makeRoomIfNeeded();
      // ReadUnique fetches the line and the right to write it in one
      // transaction.
      req.opcode     = REQ_READ_UNIQUE;
      req.expCompAck = 1'b1;
      issueWithRetry(req, txnId, item);
      collectReadData(txnId, item, rsp, dat, lineBytes);
      cache.writeLine(item.addr, lineBytes);
      cache.updateOnCompletion(item.addr, dat.resp);
      item.completionResp = dat.resp;
      item.completionErr  = dat.respErr;
      sendCompAck(txnId, dat.srcId, dat.dbId);
    end

    applyStore(item.addr);
    freeTxnId(txnId);
  endtask

  // An I/O coherent Requester holds nothing, so every access goes to the
  // fabric and none of it is snooped [SPEC:IHI0050H B1.6.1].
  protected task runIoCoherentAccess(chiRequesterTx item);
    chi_req_flit_t req;
    chi_rsp_flit_t rsp;
    chi_dat_flit_t dat;
    chiTxnIdT      txnId;
    chiLineBytesT  lineBytes;

    allocateTxnId(txnId);
    req = baseRequest(item, txnId);

    if (item.accessKind == CHI_ACCESS_READ) begin
      // ReadOnce takes a snapshot without acquiring any coherent state, which
      // is the only kind of read an I/O coherent master may issue.
      req.opcode     = REQ_READ_ONCE;
      req.expCompAck = 1'b1;
      issueWithRetry(req, txnId, item);
      collectReadData(txnId, item, rsp, dat, lineBytes);
      item.completionResp = dat.resp;
      item.completionErr  = dat.respErr;
      sendCompAck(txnId, dat.srcId, dat.dbId);
    end else begin
      // WriteUniqueFull pushes a whole line without ever holding it.
      req.opcode     = REQ_WRITE_UNIQUE_FULL;
      req.expCompAck = 1'b0;
      issueWithRetry(req, txnId, item);
      storeSerial++;
      runWriteDataPhase(txnId, item, DAT_NON_COPY_BACK_WR_DATA,
                        storePattern(item.addr, storeSerial));
    end

    freeTxnId(txnId);
  endtask

  // -------------------------------------------------------------------------
  // Eviction
  // -------------------------------------------------------------------------
  // A full cache has to give up a line before it can take another. A dirty
  // line has to be written back, because this Requester holds the only current
  // copy; a clean one can be dropped with an Evict, which tells the Home to
  // stop believing this Requester has it [SPEC:IHI0050H B2.3.1].
  protected task makeRoomIfNeeded();
    chiAddrT victim;
    if (!cache.isFull()) return;
    if (!cache.selectVictim(victim)) begin
      // Every resident line is mid-transaction. Waiting is correct: one of
      // them will complete and become evictable.
      while (cache.isFull() && !cache.selectVictim(victim)) bfm.waitCycles(1);
      if (!cache.isFull()) return;
    end
    runEviction(victim);
  endtask

  // `claimed` says the caller already holds the line, which the access
  // dispatcher does and the capacity eviction below does not.
  protected task runEviction(chiAddrT addr, bit claimed = 1'b0);
    chi_req_flit_t   req;
    chi_rsp_flit_t   rsp;
    chiTxnIdT        txnId;
    chiRequesterTx   dummy;
    bit              dirty;

    if (!cache.isValid(addr)) return;
    if (!claimed && cache.isOutstanding(addr)) return;

    dirty = cache.isDirty(addr);
    dummy = chiRequesterTx::type_id::create("evictTx");
    dummy.addr      = addr;
    dummy.size      = 3'd6;
    dummy.qos       = 4'd0;
    dummy.agentId   = cfg.agentId;
    dummy.nodeClass = cfg.nodeClass;

    allocateTxnId(txnId);
    if (!claimed) cache.markOutstanding(addr);
    req        = baseRequest(dummy, txnId);
    req.opcode = dirty ? REQ_WRITE_BACK_FULL : REQ_EVICT;
    // Neither carries CompAck: the Home completes them on its own.
    req.expCompAck = 1'b0;

    issueWithRetry(req, txnId, dummy);

    if (dirty) begin
      runWriteDataPhase(txnId, dummy, DAT_COPY_BACK_WR_DATA,
                        cache.readLine(addr));
    end else begin
      waitForResponse(txnId, rsp);
      if (rsp.opcode != RSP_COMP)
        `uvm_error(get_type_name(),
                   $sformatf("Evict expected Comp, saw %s", rsp.opcode.name()))
    end

    if (!claimed) cache.clearOutstanding(addr);
    cache.invalidate(addr);
    freeTxnId(txnId);
    `uvm_info(get_type_name(),
              $sformatf("evicted 0x%0h with %s", addr, req.opcode.name()),
              UVM_HIGH)
  endtask

  // -------------------------------------------------------------------------
  // Request issue, including retry
  // -------------------------------------------------------------------------
  // The Home Node answers a request it has no room for with RetryAck rather
  // than dropping it, and the Requester must then wait for a P-Credit and send
  // the request again with AllowRetry clear and the granted credit type echoed
  // back [SPEC:IHI0050H B2.10, B2.10.1]. Without this the transaction would
  // simply vanish whenever the fabric was busy.
  protected task issueWithRetry(ref chi_req_flit_t req, input chiTxnIdT txnId,
                                inout chiRequesterTx item);
    chi_rsp_flit_t rsp;
    bit            accepted;
    string         key;

    accepted = 1'b0;
    while (!accepted) begin
      bfm.sendRequest(req);
      transactionsIssued++;

      if (!req.allowRetry) begin
        // A credited request cannot be retried again, so nothing more to do.
        accepted = 1'b1;
        break;
      end

      // Either this request was taken or it was refused with RetryAck. The
      // refusal always arrives on RSP, but acceptance cannot be detected there:
      // an accepted read is answered with CompData on DAT and sends nothing at
      // all on RSP [SPEC:IHI0050H B2.3.1]. So both channels are watched, and
      // with peek rather than get so that whichever arrives stays in its
      // mailbox for the caller to read normally.
      fork begin
        fork
          begin : watchRsp
            chi_rsp_flit_t peekedRsp;
            rspMbox[txnId].peek(peekedRsp);
          end
          begin : watchDat
            chi_dat_flit_t peekedDat;
            datMbox[txnId].peek(peekedDat);
          end
        join_any
        disable fork;
      end join

      accepted = 1'b1;
      if (rspMbox[txnId].num() != 0) begin
        rspMbox[txnId].peek(rsp);
        if (rsp.opcode == RSP_RETRY_ACK) begin
          void'(rspMbox[txnId].try_get(rsp));
          accepted = 1'b0;
        end
      end

      if (!accepted) begin
        retriesSeen++;
        item.retryCount++;
        key = pCrdKey(rsp.srcId, rsp.pCrdType);
        `uvm_info(get_type_name(),
                  $sformatf("RetryAck on TxnID 0x%0h from 0x%0h type %0h",
                            txnId, rsp.srcId, rsp.pCrdType), UVM_HIGH)
        // Wait for a credit of the type the Home asked for.
        while (!pCrdPool.exists(key) || (pCrdPool[key] == 0))
          bfm.waitCycles(1);
        pCrdPool[key]--;
        // Re-send the same transaction, now carrying the credit. AllowRetry
        // must be clear, and PCrdType must echo what was granted.
        req.allowRetry = 1'b0;
        req.pCrdType   = rsp.pCrdType;
        req.tgtId      = rsp.srcId;
      end
    end
  endtask

  protected function chi_req_flit_t baseRequest(chiRequesterTx item,
                                                chiTxnIdT txnId);
    chi_req_flit_t req;
    req        = '0;
    req.qos    = item.qos;
    // TgtID is filled in by the fabric's System Address Map from the address,
    // so the Requester does not have to know which Home owns the line
    // [CFGDOC:#5.2]. It is set for a credited re-send, where the Home is known.
    req.tgtId  = '0;
    req.srcId  = cfg.nodeId;
    req.txnId  = txnId;
    req.addr   = item.addr;
    req.size   = item.size;
    req.pas    = PAS_NON_SECURE;
    // Cacheable, allocating, snoopable device-ordered attributes for coherent
    // traffic [SPEC:IHI0050H B2.8].
    req.memAttr        = 4'b1101;
    req.snpAttrOrDoDwt = cfg.hasCache;
    req.allowRetry     = cfg.allowRetry;
    req.pCrdType       = 4'd0;
    req.order          = ORDER_NONE;
    req.likelyShared   = 1'b0;
    req.tagOp          = TAG_OP_INVALID;
    return req;
  endfunction

  protected task waitForResponse(chiTxnIdT txnId, output chi_rsp_flit_t rsp);
    rspMbox[txnId].get(rsp);
  endtask

  // -------------------------------------------------------------------------
  // Data phases
  // -------------------------------------------------------------------------
  // A read completes over as many DAT packets as the data bus needs to carry a
  // line, each tagged with the granule it holds [SPEC:IHI0050H B2.9.4].
  protected task collectReadData(chiTxnIdT txnId, inout chiRequesterTx item,
                                 output chi_rsp_flit_t rsp,
                                 output chi_dat_flit_t dat,
                                 output chiLineBytesT lineBytes);
    chi_dat_flit_t packet;
    int unsigned   received;
    int unsigned   offset;

    rsp      = '0;
    received = 0;
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++) lineBytes[i] = '0;

    while (received < CHI_DAT_PKTS_PER_LINE) begin
      datMbox[txnId].get(packet);
      if ((packet.opcode != DAT_COMP_DATA)
          && (packet.opcode != DAT_DATA_SEP_RESP)) begin
        `uvm_error(get_type_name(),
                   $sformatf("expected CompData, saw %s", packet.opcode.name()))
      end
      // DataID names the 16-byte granule this packet starts at, so it places
      // the payload within the line.
      offset = int'(packet.dataId) * 16;
      for (int unsigned b = 0; b < (CHI_DATA_W / 8); b++) begin
        if ((offset + b) < CHI_LINE_BYTES)
          lineBytes[offset + b] = packet.data[b*8 +: 8];
      end
      dat = packet;
      received++;
    end
    item.readData = dat.data;
  endtask

  // A write hands the data over only after the Home has offered a buffer to
  // put it in. DBID names that buffer and becomes the TxnID of the write data
  // [SPEC:IHI0050H B2.3.1].
  // The line is passed whole and sliced per packet here, because each packet
  // carries a different part of it: a 64-byte line over a 256-bit bus is two
  // packets of 32 bytes, not the same 32 bytes twice.
  protected task runWriteDataPhase(chiTxnIdT txnId, inout chiRequesterTx item,
                                   input chi_dat_opcode_e datOpcode,
                                   input chiLineBytesT payload);
    chi_rsp_flit_t rsp;
    chi_dat_flit_t dat;
    chiNodeIdT     homeId;
    chiTxnIdT      dbId;
    bit            haveBuffer;
    bit            haveComp;

    haveBuffer = 1'b0;
    haveComp   = 1'b0;

    // The Home may combine the buffer offer and the completion into one
    // CompDBIDResp, or send DBIDResp then Comp separately
    // [SPEC:IHI0050H B2.3.1].
    while (!haveBuffer) begin
      waitForResponse(txnId, rsp);
      case (rsp.opcode)
        RSP_COMP_DBID_RESP: begin
          haveBuffer = 1'b1;
          haveComp   = 1'b1;
        end
        RSP_DBID_RESP, RSP_DBID_RESP_ORD: haveBuffer = 1'b1;
        RSP_COMP:                          haveComp   = 1'b1;
        default:
          `uvm_error(get_type_name(),
                     $sformatf("write expected DBID, saw %s",
                               rsp.opcode.name()))
      endcase
      homeId = rsp.srcId;
      dbId   = chiTxnIdT'(rsp.dbIdOrGroupId);
    end

    for (int unsigned p = 0; p < CHI_DAT_PKTS_PER_LINE; p++) begin
      dat        = '0;
      dat.qos    = item.qos;
      dat.tgtId  = homeId;
      dat.srcId  = cfg.nodeId;
      dat.txnId  = dbId;
      dat.opcode = datOpcode;
      dat.resp   = RESP_I;
      dat.respErr = RESP_ERR_OK;
      dat.dataId = CHI_DATAID_SLOT_W'(p * datIdStep(CHI_CFG));
      dat.ccId   = '0;
      dat.be     = {64{1'b1}};
      dat.data   = lineToDataAt(payload, p);
      dat.numDat = '0;
      bfm.sendData(dat);
    end

    while (!haveComp) begin
      waitForResponse(txnId, rsp);
      if ((rsp.opcode == RSP_COMP) || (rsp.opcode == RSP_COMP_DBID_RESP))
        haveComp = 1'b1;
      else
        `uvm_error(get_type_name(),
                   $sformatf("write expected Comp, saw %s", rsp.opcode.name()))
    end

    item.completionResp = rsp.resp;
    item.completionErr  = rsp.respErr;
  endtask

  // CompAck closes a transaction the Home is holding open. Its TxnID carries
  // the DBID the completion supplied [SPEC:IHI0050H B2.3.2].
  protected task sendCompAck(chiTxnIdT txnId, chiNodeIdT homeId,
                             logic [15:0] dbId);
    chi_rsp_flit_t rsp;
    rsp         = '0;
    rsp.qos     = 4'd0;
    rsp.tgtId   = homeId;
    rsp.srcId   = cfg.nodeId;
    rsp.txnId   = chiTxnIdT'(dbId);
    rsp.opcode  = RSP_COMP_ACK;
    rsp.resp    = RESP_I;
    rsp.respErr = RESP_ERR_OK;
    `uvm_info(get_type_name(),
              $sformatf("TX CompAck to 0x%0h on DBID 0x%0h", homeId, dbId),
              UVM_DEBUG)
    bfm.sendResponse(rsp);
    `uvm_info(get_type_name(), "CompAck accepted by the link", UVM_DEBUG)
  endtask

  // -------------------------------------------------------------------------
  // Snoops
  // -------------------------------------------------------------------------
  // Only a fully coherent Requester is snooped. The response reports the state
  // the line is left in and carries the data back whenever this Requester is
  // giving up dirty data or the Home asked for it with RetToSrc
  // [SPEC:IHI0050H B4.9, B2.13.3].
  protected task snoopHandler();
    chi_snp_flit_t  snp;
    chiSnoopActionS action;
    chiAddrT        addr;
    chi_rsp_flit_t  rsp;
    chi_dat_flit_t  dat;
    chiLineBytesT   lineBytes;

    forever begin
      bfm.getSnoop(snp);
      // The snoop address omits the low three bits, which are always zero for
      // a cache line [SPEC:IHI0050H B13.10.3].
      addr   = {snp.addr, 3'b000};
      snoopLock.get(1);
      action = cache.snoopAction(addr, snp.opcode, snp.retToSrc);

      if (action.sendData) begin
        lineBytes = cache.readLine(addr);
        for (int unsigned p = 0; p < CHI_DAT_PKTS_PER_LINE; p++) begin
          dat         = '0;
          dat.qos     = snp.qos;
          dat.tgtId   = snp.srcId;
          dat.srcId   = cfg.nodeId;
          dat.txnId   = snp.txnId;
          dat.opcode  = DAT_SNP_RESP_DATA;
          dat.resp    = action.respState;
          dat.respErr = RESP_ERR_OK;
          dat.dataId  = CHI_DATAID_SLOT_W'(p * datIdStep(CHI_CFG));
          dat.be      = {64{1'b1}};
          dat.data    = lineToDataAt(lineBytes, p);
          bfm.sendData(dat);
        end
      end else begin
        rsp         = '0;
        rsp.qos     = snp.qos;
        rsp.tgtId   = snp.srcId;
        rsp.srcId   = cfg.nodeId;
        rsp.txnId   = snp.txnId;
        rsp.opcode  = RSP_SNP_RESP;
        rsp.resp    = action.respState;
        rsp.respErr = RESP_ERR_OK;
        bfm.sendResponse(rsp);
      end

      cache.applySnoop(addr, action);
      snoopLock.put(1);
      snoopsAnswered++;
      `uvm_info(get_type_name(),
                $sformatf("snoop %s on 0x%0h -> %s%s", snp.opcode.name(), addr,
                          action.nextState.name(),
                          action.sendData ? " with data" : ""), UVM_HIGH)
    end
  endtask

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  // Contents a store leaves in the line. Derived from the address, this agent
  // and a per-agent serial number, so the bytes identify who wrote them and
  // when, and any later reader of the line can be checked against them.
  protected function chiLineBytesT storePattern(chiAddrT addr,
                                                int unsigned serial);
    chiLineBytesT bytes;
    chiAddrT      base;
    base = lineBaseOf(addr);
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++)
      bytes[i] = chiByteT'(base[7:0] + chiByteT'(i)
                           + chiByteT'(cfg.agentId << 4)
                           + chiByteT'(serial));
    return bytes;
  endfunction

  // Apply a store locally: the line must already be unique, which the caller
  // has arranged, so the write is silent and simply makes the line dirty.
  protected task applyStore(chiAddrT addr);
    snoopLock.get(1);
    storeSerial++;
    cache.writeLine(addr, storePattern(addr, storeSerial));
    cache.markDirtyAfterStore(addr);
    snoopLock.put(1);
  endtask

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
              $sformatf({"%s agent %0d: %0d requests issued, %0d retried, ",
                         "%0d snoops answered, %s"},
                        cfg.nodeClass.name(), cfg.agentId, transactionsIssued,
                        retriesSeen, snoopsAnswered,
                        (cache != null) ? cache.convert2string() : "no cache"),
              UVM_LOW)
  endfunction
endclass
