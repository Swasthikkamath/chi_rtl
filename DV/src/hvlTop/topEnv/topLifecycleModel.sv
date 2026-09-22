// Transaction lifecycle. Outstanding requests are tracked from the
// flits on each port. Nothing here predicts which home or subordinate
// a request was routed to. At the end every map is empty.
// [TOP:reqToNoc] [ASSUMPTION:8] [ASSUMPTION:14] [ASSUMPTION:18]
// See OPEN QUESTIONS Q6.

typedef struct packed {
  logic [31:0] ordinal;
  chiTxnIdT txnId;
} topTxnKeyT;

class topOpenTxn;
  chiTxnIdT txnId;
  chiTxnIdT dbId;
  chiReqOpcodeE opcode;
  chiAddrT addr;
  logic [SIZE_W-1:0] size;
  logic [ORDER_W-1:0] order;
  bit expCompAck;
  bit gotComp;
  bit gotDbid;
  bit sawReceipt;
  bit acked;
  bit retrying;
  int unsigned readLeft;
  int unsigned writeLeft;

  function new();
    gotComp = 1'b0;
    gotDbid = 1'b0;
    sawReceipt = 1'b0;
    acked = 1'b0;
    retrying = 1'b0;
    readLeft = 0;
    writeLeft = 0;
    dbId = '0;
    order = '0;
    expCompAck = 1'b0;
  endfunction
endclass

class topLifecycleModel extends uvm_component;
  topOpenTxn rnTxn[topTxnKeyT];
  topOpenTxn snTxn[topTxnKeyT];
  int unsigned txReqCount[int unsigned];

  // PrefetchTgt is not a lifecycle at all, so it is counted rather than
  // tracked. A test that sent one asks for the count to prove the hint
  // reached a Subordinate, since no response would ever say so.
  int unsigned rnPrefetchCount;
  int unsigned snPrefetchCount;

  `uvm_component_utils(topLifecycleModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rnPrefetchCount = 0;
    snPrefetchCount = 0;
  endfunction

  function topTxnKeyT chiKey(input int unsigned ordinal, input chiTxnIdT txnId);
    topTxnKeyT key;
    key.ordinal = ordinal;
    key.txnId = txnId;
    return key;
  endfunction

  function bit chiNeedsRead(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_ONCE, REQ_READ_NO_SNP,
      REQ_READ_NO_SNP_SEP, REQ_READ_UNIQUE,
      REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID,
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiNeedsWrite(input chiReqOpcodeE opcode);
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

  function int unsigned chiWriteBeats(input chiReqOpcodeE opcode, input logic [SIZE_W-1:0] size);
    int unsigned bytes;
    bytes = datTransferBytes(size);
    if (opcode == REQ_ATOMIC_COMPARE)
      bytes = bytes * 2;
    if (bytes <= DAT_BYTES_PER_PACKET)
      return 1;
    return (bytes + DAT_BYTES_PER_PACKET - 1) / DAT_BYTES_PER_PACKET;
  endfunction

  function bit chiTxnDone(input topOpenTxn txn);
    if (txn.retrying)
      return 1'b0;
    if (!txn.gotComp)
      return 1'b0;
    if (txn.readLeft != 0)
      return 1'b0;
    if (txn.writeLeft != 0)
      return 1'b0;
    if (txn.expCompAck && !txn.acked)
      return 1'b0;
    return 1'b1;
  endfunction

  function void chiOpen(input topOpenTxn txn, input chiReqFlitT flit);
    txn.txnId = flit.txnId;
    txn.opcode = flit.opcode;
    txn.addr = flit.addr;
    txn.size = flit.size;
    txn.order = flit.order;
    txn.expCompAck = flit.expCompAck;
    txn.gotComp = 1'b0;
    txn.sawReceipt = 1'b0;
    txn.acked = 1'b0;
    txn.retrying = 1'b0;
    txn.readLeft = chiNeedsRead(flit.opcode) ? datPacketCount(flit.size) : 0;
    txn.writeLeft = chiNeedsWrite(flit.opcode) ? chiWriteBeats(flit.opcode, flit.size) : 0;
  endfunction

  function topOpenTxn chiFindDb(
    input bit requester,
    input int unsigned ordinal,
    input chiTxnIdT dbId,
    output bit found
  );
    if (requester) begin
      foreach (rnTxn[key]) begin
        if ((key.ordinal == ordinal) && rnTxn[key].gotDbid && (rnTxn[key].dbId == dbId)) begin
          found = 1'b1;
          return rnTxn[key];
        end
      end
    end else begin
      foreach (snTxn[key]) begin
        if ((key.ordinal == ordinal) && snTxn[key].gotDbid && (snTxn[key].dbId == dbId)) begin
          found = 1'b1;
          return snTxn[key];
        end
      end
    end
    found = 1'b0;
    return null;
  endfunction

  function void chiRetire(input bit requester);
    topTxnKeyT drop[$];
    if (requester) begin
      foreach (rnTxn[key]) begin
        if (chiTxnDone(rnTxn[key]))
          drop.push_back(key);
      end
      foreach (drop[i])
        rnTxn.delete(drop[i]);
    end else begin
      foreach (snTxn[key]) begin
        if (chiTxnDone(snTxn[key]))
          drop.push_back(key);
      end
      foreach (drop[i])
        snTxn.delete(drop[i]);
    end
  endfunction

  function void chiNoteReq(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiReqFlitT flit
  );
    topTxnKeyT key;
    if (flit.opcode == REQ_LCRD_RETURN)
      return;
    if (nodeClassIsRequester(nodeClass) && isTx) begin
      if (!txReqCount.exists(ordinal))
        txReqCount[ordinal] = 0;
      txReqCount[ordinal]++;
      if (flit.opcode == REQ_P_CRD_RETURN)
        return;
      // A PrefetchTgt gets no response and no RetryAck, and must carry
      // TxnID 0, which is the one TxnID a Requester may use while another
      // transaction still holds it. Opening a transaction for it would
      // leave an entry nothing can ever retire, and would collide with the
      // real transaction using TxnID 0.
      // [SPEC:IHI0050H B4.2.6.2] [SPEC:IHI0050H B2.4.2]
      if (flit.opcode == REQ_PREFETCH_TGT) begin
        rnPrefetchCount++;
        if (flit.txnId != '0)
          `uvm_error("topLifecycleModel",
            {$sformatf("RN ordinal %0d sent PrefetchTgt with TxnID %0h; B4.2.6.2 requires 0",
              ordinal, flit.txnId)})
        return;
      end
      key = chiKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key))
        rnTxn[key] = new();
      chiOpen(rnTxn[key], flit);
    end
    if (!nodeClassIsRequester(nodeClass) && !isTx) begin
      if (flit.opcode == REQ_P_CRD_RETURN)
        return;
      if (flit.opcode == REQ_PREFETCH_TGT) begin
        snPrefetchCount++;
        return;
      end
      key = chiKey(ordinal, flit.txnId);
      if (!snTxn.exists(key))
        snTxn[key] = new();
      chiOpen(snTxn[key], flit);
    end
  endfunction

  function void chiApplyRsp(input topOpenTxn txn, input chiRspFlitT flit);
    if (flit.opcode == RSP_RETRY_ACK) begin
      txn.retrying = 1'b1;
      txn.gotComp = 1'b0;
      txn.gotDbid = 1'b0;
      txn.readLeft = chiNeedsRead(txn.opcode) ? datPacketCount(txn.size) : 0;
      txn.writeLeft = chiNeedsWrite(txn.opcode) ? chiWriteBeats(txn.opcode, txn.size) : 0;
      return;
    end
    if (flit.opcode == RSP_READ_RECEIPT) begin
      txn.sawReceipt = 1'b1;
      return;
    end
    if (flit.opcode == RSP_P_CRD_GRANT)
      return;
    if ((flit.opcode == RSP_DBID_RESP) || (flit.opcode == RSP_DBID_RESP_ORD)
        || (flit.opcode == RSP_COMP_DBID_RESP)) begin
      txn.gotDbid = 1'b1;
      txn.dbId = flit.dbId;
    end
    if ((flit.opcode == RSP_COMP) || (flit.opcode == RSP_COMP_DBID_RESP)
        || (flit.opcode == RSP_COMP_CMO) || (flit.opcode == RSP_RESP_SEP_DATA)
        || (flit.opcode == RSP_COMP_PERSIST))
      txn.gotComp = 1'b1;
  endfunction

  function void chiNoteRsp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    topTxnKeyT key;
    bit found;
    topOpenTxn txn;
    if (flit.opcode == RSP_LCRD_RETURN)
      return;
    if ((flit.opcode == RSP_SNP_RESP) || (flit.opcode == RSP_SNP_RESP_FWDED))
      return;
    if (nodeClassIsRequester(nodeClass) && !isTx) begin
      if (flit.opcode == RSP_P_CRD_GRANT)
        return;
      key = chiKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key)) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d RSP %s txnId %0h has no request",
            ordinal, flit.opcode.name(), flit.txnId)})
        return;
      end
      chiApplyRsp(rnTxn[key], flit);
      if ((rnTxn[key].order != '0) && rnTxn[key].sawReceipt == 1'b0
          && rnTxn[key].gotComp && chiNeedsRead(rnTxn[key].opcode))
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d completed an ordered read before ReadReceipt", ordinal)})
      chiRetire(1'b1);
      return;
    end
    if (nodeClassIsRequester(nodeClass) && isTx && (flit.opcode == RSP_COMP_ACK)) begin
      txn = chiFindDb(1'b1, ordinal, flit.txnId, found);
      if (!found) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d CompAck dbId %0h has no request", ordinal, flit.txnId)})
        return;
      end
      txn.acked = 1'b1;
      chiRetire(1'b1);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && isTx) begin
      if (flit.opcode == RSP_P_CRD_GRANT)
        return;
      key = chiKey(ordinal, flit.txnId);
      if (!snTxn.exists(key)) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("SN ordinal %0d RSP %s txnId %0h has no request",
            ordinal, flit.opcode.name(), flit.txnId)})
        return;
      end
      chiApplyRsp(snTxn[key], flit);
      chiRetire(1'b0);
    end
    if (!nodeClassIsRequester(nodeClass) && !isTx && (flit.opcode == RSP_COMP_ACK)) begin
      txn = chiFindDb(1'b0, ordinal, flit.txnId, found);
      if (!found) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("SN ordinal %0d CompAck dbId %0h has no request", ordinal, flit.txnId)})
        return;
      end
      txn.acked = 1'b1;
      chiRetire(1'b0);
    end
  endfunction

  function void chiNoteDat(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    topTxnKeyT key;
    bit found;
    topOpenTxn txn;
    if (flit.opcode == DAT_LCRD_RETURN)
      return;
    if ((flit.opcode == DAT_SNP_RESP_DATA) || (flit.opcode == DAT_SNP_RESP_DATA_PTL)
        || (flit.opcode == DAT_SNP_RESP_DATA_FWDED))
      return;
    if (nodeClassIsRequester(nodeClass) && !isTx) begin
      key = chiKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key)) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d DAT %s txnId %0h has no request",
            ordinal, flit.opcode.name(), flit.txnId)})
        return;
      end
      txn = rnTxn[key];
      if (txn.readLeft > 0)
        txn.readLeft--;
      if ((txn.order != '0) && !txn.sawReceipt)
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d read data arrived before ReadReceipt", ordinal)})
      if ((flit.opcode == DAT_COMP_DATA) || (flit.opcode == DAT_DATA_SEP_RESP)) begin
        txn.gotComp = 1'b1;
        txn.gotDbid = 1'b1;
        txn.dbId = flit.dbId;
      end
      chiRetire(1'b1);
      return;
    end
    if (nodeClassIsRequester(nodeClass) && isTx) begin
      txn = chiFindDb(1'b1, ordinal, flit.txnId, found);
      if (!found) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("RN ordinal %0d write DAT txnId %0h has no DBID", ordinal, flit.txnId)})
        return;
      end
      if (txn.writeLeft > 0)
        txn.writeLeft--;
      chiRetire(1'b1);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && isTx) begin
      key = chiKey(ordinal, flit.txnId);
      if (!snTxn.exists(key)) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("SN ordinal %0d DAT %s txnId %0h has no request",
            ordinal, flit.opcode.name(), flit.txnId)})
        return;
      end
      txn = snTxn[key];
      if (txn.readLeft > 0)
        txn.readLeft--;
      if ((flit.opcode == DAT_COMP_DATA) || (flit.opcode == DAT_DATA_SEP_RESP)) begin
        txn.gotComp = 1'b1;
        txn.gotDbid = 1'b1;
        txn.dbId = flit.dbId;
      end
      chiRetire(1'b0);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && !isTx) begin
      txn = chiFindDb(1'b0, ordinal, flit.txnId, found);
      if (!found) begin
        `uvm_error("topLifecycleModel",
          {$sformatf("SN ordinal %0d write DAT txnId %0h has no DBID", ordinal, flit.txnId)})
        return;
      end
      if (flit.opcode == DAT_WRITE_DATA_CANCEL)
        txn.writeLeft = 0;
      else if (txn.writeLeft > 0)
        txn.writeLeft--;
      chiRetire(1'b0);
    end
  endfunction

  function void chiCheckEnd();
    foreach (rnTxn[key]) begin
      `uvm_error("topLifecycleModel",
        {$sformatf("RN ordinal %0d txnId %0h opcode %s still outstanding",
          key.ordinal, key.txnId, rnTxn[key].opcode.name())})
    end
    foreach (snTxn[key]) begin
      `uvm_error("topLifecycleModel",
        {$sformatf("SN ordinal %0d txnId %0h opcode %s still outstanding",
          key.ordinal, key.txnId, snTxn[key].opcode.name())})
    end
  endfunction
endclass
