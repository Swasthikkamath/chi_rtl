// Memory reference model. Bytes live by address, not by subordinate
// port, and a byte that was never written comes from chiMemInitData.
// The image is updated only from write data observed at a subordinate
// and from WriteZero completions. Coherent read data is not compared,
// because it may have been snooped from a cache. Atomics are not
// compared. [ASSUMPTION:8] [ASSUMPTION:10] [ASSUMPTION:18]
// See OPEN QUESTIONS Q8 Q18.

typedef struct packed {
  logic [31:0] ordinal;
  chiTxnIdT txnId;
} topMemKeyT;

class topMemTxn;
  chiReqOpcodeE opcode;
  chiAddrT addr;
  logic [SIZE_W-1:0] size;
  chiTxnIdT dbId;
  bit gotDbid;
  bit completed;
  bit cancelled;
  logic [7:0] pendByte[int unsigned];

  function new();
    gotDbid = 1'b0;
    completed = 1'b0;
    cancelled = 1'b0;
    dbId = '0;
    size = '0;
    addr = '0;
  endfunction
endclass

class topMemoryModel extends uvm_component;
  logic [7:0] image[chiAddrT];
  topMemTxn rnTxn[topMemKeyT];
  topMemTxn snTxn[topMemKeyT];
  int unsigned poisonBeats;
  int unsigned dataCheckBeats;
  bit expectPoison;
  bit expectDataCheck;

  `uvm_component_utils(topMemoryModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    poisonBeats = 0;
    dataCheckBeats = 0;
    expectPoison = 1'b0;
    expectDataCheck = 1'b0;
  endfunction

  function topMemKeyT chiMemKey(input int unsigned ordinal, input chiTxnIdT txnId);
    topMemKeyT key;
    key.ordinal = ordinal;
    key.txnId = txnId;
    return key;
  endfunction

  function bit chiIsAtomicOp(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiIsWriteZero(input chiReqOpcodeE opcode);
    return (opcode == REQ_WRITE_NO_SNP_ZERO) || (opcode == REQ_WRITE_UNIQUE_ZERO);
  endfunction

  function bit chiCommitsWrite(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
      REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL,
      REQ_WRITE_UNIQUE_FULL_STASH, REQ_WRITE_UNIQUE_PTL_STASH,
      REQ_WRITE_BACK_FULL, REQ_WRITE_BACK_PTL,
      REQ_WRITE_CLEAN_FULL,
      REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiCompareRead(input chiReqOpcodeE opcode);
    return (opcode == REQ_READ_NO_SNP) || (opcode == REQ_READ_NO_SNP_SEP);
  endfunction

  // Same reset byte the subordinate store uses, copied here so the two
  // objects never share state. A byte this model has written wins.
  function logic [7:0] chiByteAt(input chiAddrT addr);
    chiAddrT line;
    int unsigned offset;
    if (image.exists(addr))
      return image[addr];
    line = lineAlign(addr);
    offset = int'(addr - line);
    return 8'hA5 ^ line[15:8] ^ line[7:0] ^ 8'(offset);
  endfunction

  function void chiZeroTransfer(input chiAddrT addr, input logic [SIZE_W-1:0] size);
    int unsigned nbytes;
    nbytes = datTransferBytes(size);
    for (int unsigned i = 0; i < nbytes; i++)
      image[addr + i] = 8'h00;
  endfunction

  function void chiFlushPending(input topMemTxn txn);
    chiAddrT line;
    if (txn.cancelled || !chiCommitsWrite(txn.opcode))
      return;
    line = lineAlign(txn.addr);
    foreach (txn.pendByte[offset])
      image[line + offset] = txn.pendByte[offset];
    txn.pendByte.delete();
  endfunction

  function void chiOpen(input topMemTxn txn, input chiReqFlitT flit);
    txn.opcode = flit.opcode;
    txn.addr = flit.addr;
    txn.size = flit.size;
    txn.gotDbid = 1'b0;
    txn.completed = 1'b0;
    txn.cancelled = 1'b0;
    txn.dbId = '0;
    txn.pendByte.delete();
  endfunction

  function topMemTxn chiFindDb(
    input int unsigned ordinal,
    input chiTxnIdT dbId,
    output bit found
  );
    foreach (snTxn[key]) begin
      if ((key.ordinal == ordinal) && snTxn[key].gotDbid && (snTxn[key].dbId == dbId)) begin
        found = 1'b1;
        return snTxn[key];
      end
    end
    found = 1'b0;
    return null;
  endfunction

  function void chiNoteReq(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiReqFlitT flit
  );
    topMemKeyT key;
    if ((flit.opcode == REQ_LCRD_RETURN) || (flit.opcode == REQ_P_CRD_RETURN))
      return;
    if (nodeClassIsRequester(nodeClass) && isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key))
        rnTxn[key] = new();
      chiOpen(rnTxn[key], flit);
    end
    if (!nodeClassIsRequester(nodeClass) && !isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!snTxn.exists(key))
        snTxn[key] = new();
      chiOpen(snTxn[key], flit);
    end
  endfunction

  function void chiNoteDbid(input topMemTxn txn, input chiRspFlitT flit);
    if ((flit.opcode == RSP_DBID_RESP) || (flit.opcode == RSP_DBID_RESP_ORD)
        || (flit.opcode == RSP_COMP_DBID_RESP)) begin
      txn.gotDbid = 1'b1;
      txn.dbId = flit.dbId;
    end
  endfunction

  function void chiNoteComplete(input topMemTxn txn);
    txn.completed = 1'b1;
    if (chiIsWriteZero(txn.opcode))
      chiZeroTransfer(txn.addr, txn.size);
    else
      chiFlushPending(txn);
  endfunction

  function bit chiIsComp(input chiRspOpcodeE opcode);
    return (opcode == RSP_COMP) || (opcode == RSP_COMP_DBID_RESP)
      || (opcode == RSP_COMP_CMO) || (opcode == RSP_RESP_SEP_DATA)
      || (opcode == RSP_COMP_PERSIST);
  endfunction

  function void chiNoteRsp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    topMemKeyT key;
    if (flit.opcode == RSP_LCRD_RETURN)
      return;
    if (nodeClassIsRequester(nodeClass) && !isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key))
        return;
      chiNoteDbid(rnTxn[key], flit);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!snTxn.exists(key))
        return;
      chiNoteDbid(snTxn[key], flit);
      if (chiIsComp(flit.opcode))
        chiNoteComplete(snTxn[key]);
    end
  endfunction

  function void chiNotePoison(input chiDatFlitT flit);
    if (flit.poison != '0)
      poisonBeats++;
    if (flit.dataCheck != '0)
      dataCheckBeats++;
  endfunction

  function void chiBufferBeat(input topMemTxn txn, input chiDatFlitT flit);
    int unsigned base;
    if (txn.cancelled || chiIsAtomicOp(txn.opcode) || !chiCommitsWrite(txn.opcode))
      return;
    if (flit.opcode == DAT_WRITE_DATA_CANCEL) begin
      txn.cancelled = 1'b1;
      txn.pendByte.delete();
      return;
    end
    base = int'(flit.dataId) * 16;
    for (int unsigned i = 0; i < BE_W; i++) begin
      if (flit.be[i])
        txn.pendByte[base + i] = flit.data[(i * 8) +: 8];
    end
    if (txn.completed)
      chiFlushPending(txn);
  endfunction

  function void chiCompareBeat(input topMemTxn txn, input chiDatFlitT flit);
    int unsigned base;
    bit mismatch;
    if (!chiCompareRead(txn.opcode) || chiIsAtomicOp(txn.opcode))
      return;
    if ((flit.respErr == RESP_ERR_DERR) || (flit.respErr == RESP_ERR_NDERR))
      return;
    if ((flit.opcode != DAT_COMP_DATA) && (flit.opcode != DAT_DATA_SEP_RESP))
      return;
    base = int'(flit.dataId) * 16;
    mismatch = 1'b0;
    for (int unsigned i = 0; i < BE_W; i++) begin
      chiAddrT byteAddr;
      if (!flit.be[i])
        continue;
      byteAddr = lineAlign(txn.addr) + base + i;
      if (flit.data[(i * 8) +: 8] !== chiByteAt(byteAddr))
        mismatch = 1'b1;
    end
    if (mismatch)
      `uvm_error("topMemoryModel",
        {$sformatf("read data mismatch addr %0h opcode %s dataId %0h",
          txn.addr, txn.opcode.name(), flit.dataId)})
  endfunction

  function void chiNoteDat(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    topMemKeyT key;
    bit found;
    topMemTxn txn;
    if (flit.opcode == DAT_LCRD_RETURN)
      return;
    chiNotePoison(flit);
    if ((flit.opcode == DAT_SNP_RESP_DATA) || (flit.opcode == DAT_SNP_RESP_DATA_PTL)
        || (flit.opcode == DAT_SNP_RESP_DATA_FWDED))
      return;
    if (nodeClassIsRequester(nodeClass) && !isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!rnTxn.exists(key))
        return;
      if ((flit.opcode == DAT_COMP_DATA) || (flit.opcode == DAT_DATA_SEP_RESP)) begin
        rnTxn[key].gotDbid = 1'b1;
        rnTxn[key].dbId = flit.dbId;
      end
      chiCompareBeat(rnTxn[key], flit);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && isTx) begin
      key = chiMemKey(ordinal, flit.txnId);
      if (!snTxn.exists(key))
        return;
      chiCompareBeat(snTxn[key], flit);
      return;
    end
    if (!nodeClassIsRequester(nodeClass) && !isTx) begin
      txn = chiFindDb(ordinal, flit.txnId, found);
      if (!found)
        return;
      chiBufferBeat(txn, flit);
    end
  endfunction

  function void chiCheckEnd();
    if (expectPoison && (poisonBeats == 0))
      `uvm_error("topMemoryModel", "expected a poisoned data beat and saw none")
    if (!expectPoison && (poisonBeats != 0))
      `uvm_error("topMemoryModel",
        {$sformatf("unexpected poisoned data beats: %0d", poisonBeats)})
    if (expectDataCheck && (dataCheckBeats == 0))
      `uvm_error("topMemoryModel", "expected a non-zero dataCheck and saw none")
    if (!expectDataCheck && (dataCheckBeats != 0))
      `uvm_error("topMemoryModel",
        {$sformatf("unexpected dataCheck beats: %0d", dataCheckBeats)})
  endfunction
endclass
