//==============================================================================
// topMemoryModel
//
// The data-integrity reference model. It answers one question: can every data
// byte that moved across the boundary be explained by something that was
// legitimately written, and — when the traffic is simple enough — is it
// exactly the byte the specification says must come back?
//
// What the boundary shows, and what it does not:
//
//   The DUT's Homes cache and forward data internally, so a read can be
//   answered by the subordinate's memory, by a Home's cache, or by another
//   RN-F through a snoop. The scoreboard cannot see which, and cannot see the
//   order in which the Home serialised racing operations. Two checks are
//   built on what *is* observable:
//
//   PROVENANCE (every line, always). A byte value is legal to observe only if
//   it is the initialisation pattern or some write was observed carrying it
//   for that address: the DUT transports and stores data but never invents
//   it, and this testbench's requesters never modify cached data silently
//   (chiRequesterCacheModel only ever stores bus-observed data), so every
//   legal value crosses a boundary at least once. Per byte address the model
//   keeps the set of values ever written; the set only grows, so membership
//   is checked at end of test, when every monitor queue has been drained and
//   no cross-port observation skew can acquit a fabrication. This catches
//   corrupted, misrouted and X-propagated data, including on the write path:
//   the bytes a subordinate receives must be bytes some requester was seen
//   sending for that address.
//
//   EXACT (single-writer lines). When every observed write to a line came
//   from one requester node, that node's own REQ channel order is the order
//   the Home serialised the line in (a CHI link is FIFO per channel, and the
//   Home is the serialisation point for a line), so the line's content is
//   exactly computable at any request time: the initialisation pattern
//   overlaid by those of the node's writes whose operative request preceded
//   it. A read from that node must then return exactly those bytes — a stale
//   or torn answer is a real bug, not a race. The operative request of a
//   retried transaction is its AllowRetry=0 reissue, so the request time used
//   is the last REQ observed for the transaction. Reads from other nodes of
//   a single-writer line, and everything on multi-writer lines, fall back to
//   the provenance check: cross-port arrival order at the Home is not
//   observable, so nothing stronger is sound.
//
//   Atomics are read-modify-writes whose result depends on the old value.
//   The operand is observed in the requester's write data. At end of test the
//   result is computed exactly inside the single-writer walk, and for
//   multi-writer lines it is computed over every old-value combination the
//   byte sets admit (capped; a cap overflow marks the word accept-all and is
//   counted, never silently dropped). Either way the result joins the
//   provenance set so later reads of it are checkable.
//
// A transaction never spans two lines: stimulus addresses are size-aligned
// and size is at most 64 bytes (chiRequesterTx.chiLegalIntent), so all
// tracking is per 64-byte line. DVM operations carry no memory content and
// are ignored here. WriteDataCancel marks its write record cancelled; a
// cancelled write changes no memory and is excluded from the exact walk and
// the writer set.
//
// Feeding order caveat: samples arrive per port, not in global time order.
// Everything order-sensitive (the exact walk, atomic results) is therefore
// computed at end of test from recorded request times, and everything else
// is order-free by construction (the provenance set only grows).
// [SPEC:IHI0050H B4.2, B4.8] [ASSUMPTION:8] [ASSUMPTION:15]
//==============================================================================

// What kind of data movement one observed DAT flit (or beat) represents.
typedef enum bit [2:0] {
  MEM_OBS_READ_REQ,   // read data delivered to a requester (DUT-driven)
  MEM_OBS_READ_SUB,   // read data leaving a subordinate (bench-driven)
  MEM_OBS_SNP_DATA,   // snoop data leaving a requester (bench-driven)
  MEM_OBS_COPYBACK,   // copyback data leaving a requester (bench-driven)
  MEM_OBS_WRITE_SUB   // write data arriving at a subordinate (DUT-driven)
} topMemObsKindE;

// One observed data beat, checked at end of test.
class topMemObs;
  topMemObsKindE kind;
  int unsigned   node;
  time           t;
  time           reqTime;      // READ_REQ only: the operative request time
  chiAddrT       line;
  logic [7:0]    bytes[64];
  bit            valid[64];
  bit            exactChecked; // set when the exact walk already judged it
endclass

// One memory-changing operation, assembled from its request and its data
// beats, in request order for the end-of-test walk.
class topMemWriteRec;
  int unsigned   node;
  time           reqTime;
  bit            cancelled;
  bit            isAtomic;
  chiReqOpcodeE  opcode;
  chiAddrT       addr;         // zero-fill base or atomic operand address
  logic [chiGlobalsPkg::SIZE_W-1:0] size;
  bit [7:0]      bytes[64];    // write data, or the atomic operand in place
  bit            covered[64];
endclass

// Everything the model knows about one 64-byte line.
class topMemLineRec;
  topMemWriteRec writes[$];
  topMemObs      reads[$];     // MEM_OBS_READ_REQ
  topMemObs      others[$];    // every other observation kind
endclass

// One open requester transaction, keyed by (node, TxnID).
class topMemReq;
  chiReqOpcodeE  opcode;
  chiAddrT       addr;
  logic [chiGlobalsPkg::SIZE_W-1:0] size;
  time           reqTime;      // last REQ observed: the operative attempt
  bit            complete;
  bit            isAtomic;
  bit            isDvm;
  int unsigned   readBeats;
  topMemWriteRec wrRec;        // the write record this transaction fills
endclass

class topMemoryModel extends uvm_component;

  topEnvConfig cfg;

  topMemReq    reqByKey[int unsigned];        // reqKey: node * 2^TXN_ID + txnId
  int unsigned dbidToReq[longint unsigned];   // (node, Home, DBID) -> reqKey
  topMemReq    serveByKey[longint unsigned];  // (node, SrcID, TxnID) -> serve
  longint unsigned serveOfDbid[int unsigned]; // (node, DBID) -> serveKey
  chiAddrT     snpLine[int unsigned];         // (node, snoop TxnID) -> line
  topMemLineRec lines[chiAddrT];

  // The provenance set: distinct values ever written per byte address. The
  // initialisation pattern is always legal and is never stored. acceptAll is
  // set only when an atomic's old-value combinations overflow; it downgrades
  // that byte's membership check to a pass and is counted in the report.
  bit [7:0] byteValues[chiAddrT][$];
  bit       acceptAll[chiAddrT];

  int unsigned obsCount;
  int unsigned writeCount;
  int unsigned readExactCount;
  int unsigned provenanceErrorCount;
  int unsigned staleErrorCount;
  int unsigned transportErrorCount;
  int unsigned xErrorCount;
  int unsigned atomicCount;
  int unsigned acceptAllCount;

  `uvm_component_utils(topMemoryModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    obsCount = 0;
    writeCount = 0;
    readExactCount = 0;
    provenanceErrorCount = 0;
    staleErrorCount = 0;
    transportErrorCount = 0;
    xErrorCount = 0;
    atomicCount = 0;
    acceptAllCount = 0;
  endfunction

  //--------------------------------------------------------------------------
  // Key packing (same scheme as the lifecycle model; the models share no
  // state, so each packs its own)
  //--------------------------------------------------------------------------

  function automatic int unsigned reqKey(input int unsigned node,
                                         input chiTxnIdT txnId);
    return node * (32'h1 << chiGlobalsPkg::TXN_ID_W) + int'(txnId);
  endfunction

  function automatic longint unsigned serveKey(input int unsigned node,
                                               input chiNodeIdT srcId,
                                               input chiTxnIdT txnId);
    return (longint'(node) << 28) | (longint'(srcId) << 12) | longint'(txnId);
  endfunction

  function automatic longint unsigned homeDbidKey(input int unsigned node,
                                                  input chiNodeIdT home,
                                                  input chiTxnIdT dbId);
    return (longint'(node) << 28) | (longint'(home) << 12) | longint'(dbId);
  endfunction

  function automatic int unsigned subDbidKey(input int unsigned node,
                                             input chiTxnIdT dbId);
    return node * (32'h1 << chiGlobalsPkg::TXN_ID_W) + int'(dbId);
  endfunction

  //--------------------------------------------------------------------------
  // Opcode classification
  //--------------------------------------------------------------------------

  function automatic bit isAtomicOpcode(input chiReqOpcodeE op);
    case (op)
      chiGlobalsPkg::REQ_ATOMIC_STORE_ADD, chiGlobalsPkg::REQ_ATOMIC_STORE_CLR,
      chiGlobalsPkg::REQ_ATOMIC_STORE_EOR, chiGlobalsPkg::REQ_ATOMIC_STORE_SET,
      chiGlobalsPkg::REQ_ATOMIC_STORE_SMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_SMIN,
      chiGlobalsPkg::REQ_ATOMIC_STORE_UMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_UMIN,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_ADD, chiGlobalsPkg::REQ_ATOMIC_LOAD_CLR,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_EOR, chiGlobalsPkg::REQ_ATOMIC_LOAD_SET,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SMAX, chiGlobalsPkg::REQ_ATOMIC_LOAD_SMIN,
      chiGlobalsPkg::REQ_ATOMIC_LOAD_UMAX, chiGlobalsPkg::REQ_ATOMIC_LOAD_UMIN,
      chiGlobalsPkg::REQ_ATOMIC_SWAP, chiGlobalsPkg::REQ_ATOMIC_COMPARE:
        return 1'b1;
      default:
        return 1'b0;
    endcase
  endfunction

  function automatic bit isZeroOpcode(input chiReqOpcodeE op);
    return (op == chiGlobalsPkg::REQ_WRITE_UNIQUE_ZERO) ||
           (op == chiGlobalsPkg::REQ_WRITE_NO_SNP_ZERO);
  endfunction

  function automatic bit isStoreAtomic(input chiReqOpcodeE op);
    case (op)
      chiGlobalsPkg::REQ_ATOMIC_STORE_ADD, chiGlobalsPkg::REQ_ATOMIC_STORE_CLR,
      chiGlobalsPkg::REQ_ATOMIC_STORE_EOR, chiGlobalsPkg::REQ_ATOMIC_STORE_SET,
      chiGlobalsPkg::REQ_ATOMIC_STORE_SMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_SMIN,
      chiGlobalsPkg::REQ_ATOMIC_STORE_UMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_UMIN:
        return 1'b1;
      default:
        return 1'b0;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // The provenance set
  //--------------------------------------------------------------------------

  function automatic logic [7:0] initByte(input chiAddrT addr);
    logic [63:0] word;
    word = chiGlobalsPkg::chiMemInitData(addr & ~chiAddrT'(7));
    return word[(addr[2:0] * 8) +: 8];
  endfunction

  function automatic void noteByte(input chiAddrT addr, input logic [7:0] value);
    bit [7:0] v;
    if ($isunknown(value))
      return;   // an X byte is reported by the observation that carried it
    v = bit'(value);
    if (v == initByte(addr))
      return;
    if (!byteValues.exists(addr))
      byteValues[addr] = {};
    foreach (byteValues[addr][i])
      if (byteValues[addr][i] == v)
        return;
    byteValues[addr].push_back(v);
  endfunction

  function automatic bit byteKnown(input chiAddrT addr, input logic [7:0] value);
    bit [7:0] v;
    if (acceptAll.exists(addr) && acceptAll[addr])
      return 1'b1;
    if ($isunknown(value))
      return 1'b0;   // reported separately as an X error
    v = bit'(value);
    if (v == initByte(addr))
      return 1'b1;
    if (!byteValues.exists(addr))
      return 1'b0;
    foreach (byteValues[addr][i])
      if (byteValues[addr][i] == v)
        return 1'b1;
    return 1'b0;
  endfunction

  //--------------------------------------------------------------------------
  // The atomic operation, mirroring chiSubordinateMemoryModel::chiAtomic so
  // the model's arithmetic is the bench's arithmetic [ASSUMPTION:15]
  //--------------------------------------------------------------------------

  function automatic logic [63:0] lowMask(input int unsigned nbytes);
    if (nbytes >= 8)
      return {64{1'b1}};
    return (64'b1 << (nbytes * 8)) - 64'b1;
  endfunction

  function automatic logic [63:0] smaxOf(input logic [63:0] left,
      input logic [63:0] right, input int unsigned nbytes);
    logic [63:0] a;
    logic [63:0] b;
    int unsigned signBit;
    a = left & lowMask(nbytes);
    b = right & lowMask(nbytes);
    if (nbytes >= 8)
      return ($signed(a) >= $signed(b)) ? a : b;
    signBit = (nbytes * 8) - 1;
    if (a[signBit] != b[signBit])
      return a[signBit] ? b : a;
    return (a >= b) ? a : b;
  endfunction

  function automatic logic [63:0] sminOf(input logic [63:0] left,
      input logic [63:0] right, input int unsigned nbytes);
    logic [63:0] a;
    logic [63:0] b;
    int unsigned signBit;
    a = left & lowMask(nbytes);
    b = right & lowMask(nbytes);
    if (nbytes >= 8)
      return ($signed(a) <= $signed(b)) ? a : b;
    signBit = (nbytes * 8) - 1;
    if (a[signBit] != b[signBit])
      return a[signBit] ? a : b;
    return (a <= b) ? a : b;
  endfunction

  // oldv and operand are the little-endian values of the nbytes-wide field;
  // for Compare, swapv carries the second operand.
  function automatic logic [63:0] atomicWordOp(input chiReqOpcodeE opcode,
      input logic [63:0] oldv, input logic [63:0] operand,
      input logic [63:0] swapv, input int unsigned nbytes);
    logic [63:0] mask;
    logic [63:0] a;
    logic [63:0] b;
    mask = lowMask(nbytes);
    a = oldv & mask;
    b = operand & mask;
    case (opcode)
      chiGlobalsPkg::REQ_ATOMIC_LOAD_ADD, chiGlobalsPkg::REQ_ATOMIC_STORE_ADD:
        return (a + b) & mask;
      chiGlobalsPkg::REQ_ATOMIC_LOAD_CLR, chiGlobalsPkg::REQ_ATOMIC_STORE_CLR:
        return (a & ~b) & mask;
      chiGlobalsPkg::REQ_ATOMIC_LOAD_EOR, chiGlobalsPkg::REQ_ATOMIC_STORE_EOR:
        return (a ^ b) & mask;
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SET, chiGlobalsPkg::REQ_ATOMIC_STORE_SET:
        return (a | b) & mask;
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_SMAX:
        return smaxOf(a, b, nbytes);
      chiGlobalsPkg::REQ_ATOMIC_LOAD_SMIN, chiGlobalsPkg::REQ_ATOMIC_STORE_SMIN:
        return sminOf(a, b, nbytes);
      chiGlobalsPkg::REQ_ATOMIC_LOAD_UMAX, chiGlobalsPkg::REQ_ATOMIC_STORE_UMAX:
        return (a >= b) ? a : b;
      chiGlobalsPkg::REQ_ATOMIC_LOAD_UMIN, chiGlobalsPkg::REQ_ATOMIC_STORE_UMIN:
        return (a <= b) ? a : b;
      chiGlobalsPkg::REQ_ATOMIC_SWAP:
        return b;
      chiGlobalsPkg::REQ_ATOMIC_COMPARE:
        return (a == b) ? (swapv & mask) : a;
      default:
        return a;
    endcase
  endfunction

  //--------------------------------------------------------------------------
  // Observation recording
  //--------------------------------------------------------------------------

  function automatic topMemLineRec lineRec(input chiAddrT line);
    if (!lines.exists(line))
      lines[line] = new();
    return lines[line];
  endfunction

  function automatic topMemObs newObs(input topMemObsKindE kind,
      input int unsigned node, input time t, input chiAddrT line);
    topMemObs obs;
    obs = new();
    obs.kind = kind;
    obs.node = node;
    obs.t = t;
    obs.reqTime = 0;
    obs.line = line;
    obs.exactChecked = 1'b0;
    for (int unsigned i = 0; i < 64; i++) begin
      obs.bytes[i] = '0;
      obs.valid[i] = 1'b0;
    end
    obsCount++;
    return obs;
  endfunction

  // The bytes of one DAT beat that carry meaning for a transfer of
  // [addr, addr + 2^size): the beat covers line bytes [dataId*16,
  // dataId*16 + DAT_BYTES_PER_PACKET), and the intersection is what a
  // receiver may look at [ASSUMPTION:8].
  function automatic void coverRange(input topMemObs obs,
      input chiGlobalsPkg::chiDatFlitT dat, input chiAddrT addr,
      input logic [chiGlobalsPkg::SIZE_W-1:0] size);
    int unsigned base;
    int unsigned first;
    int unsigned last;
    base = int'(dat.dataId) * 16;
    first = int'(addr % chiGlobalsPkg::CACHE_LINE_BYTES);
    last = first + chiGlobalsPkg::datTransferBytes(size);
    for (int unsigned i = 0; i < chiGlobalsPkg::DAT_BYTES_PER_PACKET; i++) begin
      int unsigned lineOff;
      lineOff = base + i;
      if (lineOff >= chiGlobalsPkg::CACHE_LINE_BYTES)
        break;
      if ((lineOff >= first) && (lineOff < last)) begin
        obs.bytes[lineOff] = dat.data[(i * 8) +: 8];
        obs.valid[lineOff] = 1'b1;
      end
    end
  endfunction

  // The bytes of one DAT beat the sender marked valid: the byte enables.
  function automatic void coverBe(input topMemObs obs,
      input chiGlobalsPkg::chiDatFlitT dat);
    int unsigned base;
    base = int'(dat.dataId) * 16;
    for (int unsigned i = 0; i < chiGlobalsPkg::DAT_BYTES_PER_PACKET; i++) begin
      int unsigned lineOff;
      lineOff = base + i;
      if (lineOff >= chiGlobalsPkg::CACHE_LINE_BYTES)
        break;
      if (dat.be[i]) begin
        obs.bytes[lineOff] = dat.data[(i * 8) +: 8];
        obs.valid[lineOff] = 1'b1;
      end
    end
  endfunction

  //--------------------------------------------------------------------------
  // Requester-side handlers
  //--------------------------------------------------------------------------

  function automatic void reqTxReq(input int unsigned node,
      input chiGlobalsPkg::chiReqFlitT req, input time now);
    int unsigned key;
    topMemReq inst;
    if (req.opcode == chiGlobalsPkg::REQ_P_CRD_RETURN)
      return;
    key = reqKey(node, req.txnId);
    if (reqByKey.exists(key) && !reqByKey[key].complete) begin
      // The reissue after a RetryAck is the operative attempt: it is the
      // request the Home actually serialises, so it carries the ordering time.
      reqByKey[key].reqTime = now;
      if (reqByKey[key].wrRec != null)
        reqByKey[key].wrRec.reqTime = now;
      return;
    end
    inst = new();
    inst.opcode = req.opcode;
    inst.addr = req.addr;
    inst.size = req.size;
    inst.reqTime = now;
    inst.complete = 1'b0;
    inst.isAtomic = isAtomicOpcode(req.opcode);
    inst.isDvm = (req.opcode == chiGlobalsPkg::REQ_DVM_OP);
    inst.readBeats = 0;
    inst.wrRec = null;
    reqByKey[key] = inst;
    if (isZeroOpcode(req.opcode)) begin
      // A zero write has no data phase; its whole effect is known at the
      // request.
      topMemWriteRec wr;
      int unsigned first;
      int unsigned last;
      wr = new();
      wr.node = node;
      wr.reqTime = now;
      wr.cancelled = 1'b0;
      wr.isAtomic = 1'b0;
      wr.opcode = req.opcode;
      wr.addr = req.addr;
      wr.size = req.size;
      for (int unsigned i = 0; i < 64; i++) begin
        wr.bytes[i] = '0;
        wr.covered[i] = 1'b0;
      end
      first = int'(req.addr % chiGlobalsPkg::CACHE_LINE_BYTES);
      last = first + chiGlobalsPkg::datTransferBytes(req.size);
      for (int unsigned i = first; (i < last) && (i < 64); i++) begin
        wr.bytes[i] = 8'h00;
        wr.covered[i] = 1'b1;
        noteByte(chiGlobalsPkg::lineAlign(req.addr) + i, 8'h00);
      end
      lineRec(chiGlobalsPkg::lineAlign(req.addr)).writes.push_back(wr);
      inst.wrRec = wr;
      writeCount++;
    end
  endfunction

  function automatic void reqRxRsp(input int unsigned node,
      input chiGlobalsPkg::chiRspFlitT rsp);
    int unsigned key;
    if (rsp.opcode == chiGlobalsPkg::RSP_P_CRD_GRANT)
      return;
    key = reqKey(node, rsp.txnId);
    if (!reqByKey.exists(key))
      return;   // the lifecycle model reports the unsolicited response
    case (rsp.opcode)
      chiGlobalsPkg::RSP_DBID_RESP, chiGlobalsPkg::RSP_DBID_RESP_ORD,
      chiGlobalsPkg::RSP_COMP_DBID_RESP:
        dbidToReq[homeDbidKey(node, rsp.srcId, rsp.dbId)] = key;
      default: ;
    endcase
    case (rsp.opcode)
      chiGlobalsPkg::RSP_COMP, chiGlobalsPkg::RSP_COMP_CMO,
      chiGlobalsPkg::RSP_COMP_PERSIST, chiGlobalsPkg::RSP_PERSIST,
      chiGlobalsPkg::RSP_STASH_DONE, chiGlobalsPkg::RSP_COMP_STASH_DONE,
      chiGlobalsPkg::RSP_RESP_SEP_DATA, chiGlobalsPkg::RSP_COMP_DBID_RESP:
        reqByKey[key].complete = 1'b1;
      default: ;
    endcase
  endfunction

  function automatic void reqRxDat(input int unsigned node,
      input chiGlobalsPkg::chiDatFlitT dat, input time now);
    int unsigned key;
    topMemReq inst;
    topMemObs obs;
    if ((dat.opcode != chiGlobalsPkg::DAT_COMP_DATA) &&
        (dat.opcode != chiGlobalsPkg::DAT_DATA_SEP_RESP))
      return;
    key = reqKey(node, dat.txnId);
    if (!reqByKey.exists(key))
      return;   // unsolicited data: the lifecycle model reports it
    inst = reqByKey[key];
    if (inst.isDvm)
      return;
    obs = newObs(MEM_OBS_READ_REQ, node, now, chiGlobalsPkg::lineAlign(inst.addr));
    obs.reqTime = inst.reqTime;
    coverRange(obs, dat, inst.addr, inst.size);
    lineRec(obs.line).reads.push_back(obs);
    inst.readBeats++;
    if (inst.readBeats >= chiGlobalsPkg::datPacketCount(inst.size))
      inst.complete = 1'b1;
  endfunction

  function automatic void reqTxDat(input int unsigned node,
      input chiGlobalsPkg::chiDatFlitT dat, input time now);
    longint unsigned dkey;
    int unsigned key;
    topMemReq inst;
    topMemObs obs;
    chiAddrT line;
    case (dat.opcode)
      chiGlobalsPkg::DAT_SNP_RESP_DATA, chiGlobalsPkg::DAT_SNP_RESP_DATA_PTL: begin
        key = reqKey(node, dat.txnId);
        if (!snpLine.exists(key))
          return;   // snoop data with no snoop: the lifecycle model reports it
        line = snpLine[key];
        obs = newObs(MEM_OBS_SNP_DATA, node, now, line);
        coverBe(obs, dat);
        lineRec(line).others.push_back(obs);
        // The snooped data joins the memory system at the Home.
        for (int unsigned i = 0; i < 64; i++)
          if (obs.valid[i])
            noteByte(line + i, obs.bytes[i]);
      end
      chiGlobalsPkg::DAT_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NON_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NCB_WR_DATA_COMP_ACK: begin
        dkey = homeDbidKey(node, dat.homeNid, dat.txnId);
        if (!dbidToReq.exists(dkey))
          return;   // write data with no grant: the lifecycle model reports it
        key = dbidToReq[dkey];
        if (!reqByKey.exists(key))
          return;
        inst = reqByKey[key];
        if (inst.isDvm)
          return;   // DVM payload is not memory content
        line = chiGlobalsPkg::lineAlign(inst.addr);
        if (inst.wrRec == null) begin
          topMemWriteRec wr;
          wr = new();
          wr.node = node;
          wr.reqTime = inst.reqTime;
          wr.cancelled = 1'b0;
          wr.isAtomic = inst.isAtomic;
          wr.opcode = inst.opcode;
          wr.addr = inst.addr;
          wr.size = inst.size;
          for (int unsigned i = 0; i < 64; i++) begin
            wr.bytes[i] = '0;
            wr.covered[i] = 1'b0;
          end
          lineRec(line).writes.push_back(wr);
          inst.wrRec = wr;
          writeCount++;
          if (inst.isAtomic)
            atomicCount++;
        end
        if (inst.isAtomic) begin
          // The operand lives at the operand address, gathered regardless of
          // the byte enables (the bench's subordinate reads it that way).
          int unsigned base;
          int unsigned first;
          int unsigned last;
          base = int'(dat.dataId) * 16;
          first = int'(inst.addr % chiGlobalsPkg::CACHE_LINE_BYTES);
          last = first + int'(chiGlobalsPkg::datTransferBytes(inst.size));
          if (inst.opcode == chiGlobalsPkg::REQ_ATOMIC_COMPARE)
            last = first + 2 * int'(chiGlobalsPkg::datTransferBytes(inst.size));
          for (int unsigned i = 0; i < chiGlobalsPkg::DAT_BYTES_PER_PACKET; i++) begin
            int unsigned lineOff;
            lineOff = base + i;
            if (lineOff >= chiGlobalsPkg::CACHE_LINE_BYTES)
              break;
            if ((lineOff >= first) && (lineOff < last)) begin
              inst.wrRec.bytes[lineOff] = dat.data[(i * 8) +: 8];
              inst.wrRec.covered[lineOff] = 1'b1;
            end
          end
        end
        else begin
          obs = newObs(
            (dat.opcode == chiGlobalsPkg::DAT_COPY_BACK_WR_DATA)
              ? MEM_OBS_COPYBACK : MEM_OBS_WRITE_SUB, node, now, line);
          // A plain write's data is a source, not an observation to check;
          // only the copyback is checked, because that data claims to have
          // come from somewhere. The WRITE_SUB kind is reused below for the
          // subordinate-side transport check; a requester's own write data is
          // never membership-checked.
          coverBe(obs, dat);
          for (int unsigned i = 0; i < 64; i++) begin
            if (obs.valid[i]) begin
              inst.wrRec.bytes[i] = obs.bytes[i];
              inst.wrRec.covered[i] = 1'b1;
              noteByte(line + i, obs.bytes[i]);
            end
          end
          if (dat.opcode == chiGlobalsPkg::DAT_COPY_BACK_WR_DATA)
            lineRec(line).others.push_back(obs);
          else
            obsCount--;   // a plain write source is not a checked observation
        end
      end
      chiGlobalsPkg::DAT_WRITE_DATA_CANCEL: begin
        dkey = homeDbidKey(node, dat.homeNid, dat.txnId);
        if (!dbidToReq.exists(dkey))
          return;
        key = dbidToReq[dkey];
        if (!reqByKey.exists(key))
          return;
        inst = reqByKey[key];
        if (inst.wrRec != null)
          inst.wrRec.cancelled = 1'b1;
      end
      default: ;
    endcase
  endfunction

  function automatic void reqRxSnp(input int unsigned node,
      input chiGlobalsPkg::chiSnpFlitT snp);
    if (snp.opcode == chiGlobalsPkg::SNP_DVM_OP)
      return;   // DVM snoops carry no line state
    snpLine[reqKey(node, snp.txnId)] = chiGlobalsPkg::lineAlign(snp.addr);
  endfunction

  //--------------------------------------------------------------------------
  // Subordinate-side handlers
  //--------------------------------------------------------------------------

  function automatic void subRxReq(input int unsigned node,
      input chiGlobalsPkg::chiReqFlitT req);
    topMemReq serve;
    if (req.opcode == chiGlobalsPkg::REQ_P_CRD_RETURN)
      return;
    serve = new();
    serve.opcode = req.opcode;
    serve.addr = req.addr;
    serve.size = req.size;
    serve.reqTime = 0;
    serve.complete = 1'b0;
    serve.isAtomic = isAtomicOpcode(req.opcode);
    serve.isDvm = (req.opcode == chiGlobalsPkg::REQ_DVM_OP);
    serve.readBeats = 0;
    serve.wrRec = null;
    serveByKey[serveKey(node, req.srcId, req.txnId)] = serve;
  endfunction

  function automatic void subTxRsp(input int unsigned node,
      input chiGlobalsPkg::chiRspFlitT rsp);
    longint unsigned skey;
    case (rsp.opcode)
      chiGlobalsPkg::RSP_DBID_RESP, chiGlobalsPkg::RSP_DBID_RESP_ORD,
      chiGlobalsPkg::RSP_COMP_DBID_RESP: begin
        skey = serveKey(node, rsp.tgtId, rsp.txnId);
        if (serveByKey.exists(skey))
          serveOfDbid[subDbidKey(node, rsp.dbId)] = skey;
      end
      default: ;
    endcase
  endfunction

  function automatic void subRxDat(input int unsigned node,
      input chiGlobalsPkg::chiDatFlitT dat, input time now);
    longint unsigned skey;
    topMemReq serve;
    topMemObs obs;
    chiAddrT line;
    case (dat.opcode)
      chiGlobalsPkg::DAT_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NON_COPY_BACK_WR_DATA,
      chiGlobalsPkg::DAT_NCB_WR_DATA_COMP_ACK: ;
      default:
        return;
    endcase
    if (!serveOfDbid.exists(subDbidKey(node, dat.txnId)))
      return;
    skey = serveOfDbid[subDbidKey(node, dat.txnId)];
    if (!serveByKey.exists(skey))
      return;
    serve = serveByKey[skey];
    // An atomic's inbound data is its operand, not a memory value; its
    // provenance is the bench's stimulus, so the transport check skips it.
    if (serve.isAtomic || serve.isDvm)
      return;
    line = chiGlobalsPkg::lineAlign(serve.addr);
    obs = newObs(MEM_OBS_WRITE_SUB, node, now, line);
    coverBe(obs, dat);
    lineRec(line).others.push_back(obs);
  endfunction

  function automatic void subTxDat(input int unsigned node,
      input chiGlobalsPkg::chiDatFlitT dat, input time now);
    longint unsigned skey;
    topMemReq serve;
    topMemObs obs;
    if ((dat.opcode != chiGlobalsPkg::DAT_COMP_DATA) &&
        (dat.opcode != chiGlobalsPkg::DAT_DATA_SEP_RESP))
      return;
    skey = serveKey(node, dat.tgtId, dat.txnId);
    if (!serveByKey.exists(skey))
      return;
    serve = serveByKey[skey];
    obs = newObs(MEM_OBS_READ_SUB, node, now, chiGlobalsPkg::lineAlign(serve.addr));
    coverRange(obs, dat, serve.addr, serve.size);
    lineRec(obs.line).others.push_back(obs);
  endfunction

  //--------------------------------------------------------------------------
  // Dispatch
  //--------------------------------------------------------------------------

  function void noteFlit(input chiGlobalsPkg::chiFlitSampleT sample);
    bit isReq;
    if (!cfg.enableMemoryChecks)
      return;
    if (sample.lcrdReturn)
      return;
    isReq = chiGlobalsPkg::nodeClassIsRequester(sample.nodeClass);
    if (isReq) begin
      case ({sample.channel, sample.direction})
        {chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_TX}:
          reqTxReq(sample.nodeOrdinal, chiGlobalsPkg::unpackReq(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX}:
          reqTxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_SNP, chiGlobalsPkg::CHI_DIR_RX}:
          reqRxSnp(sample.nodeOrdinal, chiGlobalsPkg::unpackSnp(sample.payload));
        default: ;
      endcase
    end
    else begin
      case ({sample.channel, sample.direction})
        {chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_RX}:
          subRxReq(sample.nodeOrdinal, chiGlobalsPkg::unpackReq(sample.payload));
        {chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_TX}:
          subTxRsp(sample.nodeOrdinal, chiGlobalsPkg::unpackRsp(sample.payload));
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX}:
          subRxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload),
                   sample.sampleTime);
        {chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX}:
          subTxDat(sample.nodeOrdinal, chiGlobalsPkg::unpackDat(sample.payload),
                   sample.sampleTime);
        default: ;
      endcase
    end
  endfunction

  //--------------------------------------------------------------------------
  // End-of-test evaluation
  //--------------------------------------------------------------------------

  function automatic void sortWrites(input topMemLineRec rec);
    // Insertion sort by request time; a line's write list is a handful of
    // entries, and all of them left the same port, so the times are distinct
    // and totally ordered.
    for (int i = 1; i < rec.writes.size(); i++) begin
      topMemWriteRec key;
      int j;
      key = rec.writes[i];
      j = i - 1;
      while ((j >= 0) && (rec.writes[j].reqTime > key.reqTime)) begin
        rec.writes[j + 1] = rec.writes[j];
        j--;
      end
      rec.writes[j + 1] = key;
    end
  endfunction

  function automatic void sortReads(input topMemLineRec rec);
    for (int i = 1; i < rec.reads.size(); i++) begin
      topMemObs key;
      int j;
      key = rec.reads[i];
      j = i - 1;
      while ((j >= 0) && (rec.reads[j].reqTime > key.reqTime)) begin
        rec.reads[j + 1] = rec.reads[j];
        j--;
      end
      rec.reads[j + 1] = key;
    end
  endfunction

  // One write applied to the exact image.
  function automatic void applyWrite(inout bit [7:0] image[64],
                                     input topMemWriteRec wr);
    if (wr.isAtomic) begin
      int unsigned first;
      int unsigned nbytes;
      logic [63:0] oldv;
      logic [63:0] operand;
      logic [63:0] swapv;
      logic [63:0] result;
      first = int'(wr.addr % chiGlobalsPkg::CACHE_LINE_BYTES);
      nbytes = chiGlobalsPkg::datTransferBytes(wr.size);
      oldv = '0;
      operand = '0;
      swapv = '0;
      for (int unsigned i = 0; (i < nbytes) && (i < 8); i++)
        oldv[(i * 8) +: 8] = image[first + i];
      for (int unsigned i = 0; (i < nbytes) && (i < 8); i++)
        operand[(i * 8) +: 8] = wr.bytes[first + i];
      if (wr.opcode == chiGlobalsPkg::REQ_ATOMIC_COMPARE)
        for (int unsigned i = 0; (i < nbytes) && (i < 8); i++)
          swapv[(i * 8) +: 8] = wr.bytes[first + nbytes + i];
      result = atomicWordOp(wr.opcode, oldv, operand, swapv, nbytes);
      for (int unsigned i = 0; (i < nbytes) && (i < 8); i++)
        image[first + i] = result[(i * 8) +: 8];
    end
    else begin
      for (int unsigned i = 0; i < 64; i++)
        if (wr.covered[i])
          image[i] = wr.bytes[i];
    end
  endfunction

  // An atomic's result over every old value the provenance set admits, so
  // that a later read of the result is checkable even on a multi-writer line
  // where the exact walk does not run. The byte sets are tiny in practice;
  // past the cap the word's bytes go accept-all, which is counted and
  // reported rather than silently weak.
  function automatic void applyAtomicToSet(input chiAddrT line,
                                           input topMemWriteRec wr);
    int unsigned first;
    int unsigned nbytes;
    logic [63:0] operand;
    logic [63:0] swapv;
    logic [63:0] combo;
    logic [63:0] result;
    bit [7:0]    choices[8][$];
    int unsigned indexes[8];
    int unsigned combos;
    bit overflow;
    first = int'(wr.addr % chiGlobalsPkg::CACHE_LINE_BYTES);
    nbytes = chiGlobalsPkg::datTransferBytes(wr.size);
    if (nbytes > 8)
      nbytes = 8;
    operand = '0;
    swapv = '0;
    for (int unsigned i = 0; i < nbytes; i++)
      operand[(i * 8) +: 8] = wr.bytes[first + i];
    if (wr.opcode == chiGlobalsPkg::REQ_ATOMIC_COMPARE)
      for (int unsigned i = 0; i < nbytes; i++)
        swapv[(i * 8) +: 8] = wr.bytes[first + nbytes + i];
    for (int unsigned i = 0; i < nbytes; i++) begin
      chiAddrT byteAddr;
      byteAddr = line + chiAddrT'(first + i);
      choices[i] = {};
      choices[i].push_back(bit'(initByte(byteAddr)));
      if (byteValues.exists(byteAddr))
        foreach (byteValues[byteAddr][j])
          choices[i].push_back(byteValues[byteAddr][j]);
      indexes[i] = 0;
    end
    combos = 0;
    overflow = 1'b0;
    begin
      bit done;
      done = 1'b0;
      while (!done && !overflow) begin
        combo = '0;
        for (int unsigned i = 0; i < nbytes; i++)
          combo[(i * 8) +: 8] = choices[i][indexes[i]];
        result = atomicWordOp(wr.opcode, combo, operand, swapv, nbytes);
        for (int unsigned i = 0; i < nbytes; i++)
          noteByte(line + chiAddrT'(first + i), result[(i * 8) +: 8]);
        combos++;
        if (combos >= 256) begin
          overflow = 1'b1;
        end
        else begin
          int digit;
          digit = 0;
          done = 1'b1;
          while (digit < int'(nbytes)) begin
            if (indexes[digit] + 1 < choices[digit].size()) begin
              indexes[digit]++;
              done = 1'b0;
              break;
            end
            indexes[digit] = 0;
            digit++;
          end
        end
      end
    end
    if (overflow) begin
      for (int unsigned i = 0; i < nbytes; i++) begin
        chiAddrT byteAddr;
        byteAddr = line + chiAddrT'(first + i);
        if (!acceptAll.exists(byteAddr) || !acceptAll[byteAddr]) begin
          acceptAll[byteAddr] = 1'b1;
          acceptAllCount++;
        end
      end
    end
  endfunction

  function automatic void checkObsBytes(input topMemObs obs);
    string tag;
    case (obs.kind)
      MEM_OBS_READ_REQ:  tag = "MEM/PROVENANCE";
      MEM_OBS_READ_SUB:  tag = "MEM/SUBREAD";
      MEM_OBS_SNP_DATA:  tag = "MEM/SNPDATA";
      MEM_OBS_COPYBACK:  tag = "MEM/COPYBACK";
      default:           tag = "MEM/TRANSPORT";
    endcase
    for (int unsigned i = 0; i < 64; i++) begin
      if (!obs.valid[i])
        continue;
      if ($isunknown(obs.bytes[i])) begin
        xErrorCount++;
        `uvm_error("MEM/X", $sformatf(
          "line 'h%0h byte %0d: X on the data bus (node %0d, %s at %0t)",
          obs.line, i, obs.node, tag, obs.t))
        continue;
      end
      if (!byteKnown(obs.line + chiAddrT'(i), obs.bytes[i])) begin
        if (obs.kind == MEM_OBS_WRITE_SUB)
          transportErrorCount++;
        else
          provenanceErrorCount++;
        `uvm_error(tag, $sformatf(
          "line 'h%0h byte %0d: value 'h%02x was never written to that address (node %0d at %0t)",
          obs.line, i, bit'(obs.bytes[i]), obs.node, obs.t))
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!cfg.enableMemoryChecks)
      return;
    foreach (lines[line]) begin
      topMemLineRec rec;
      bit [7:0] image[64];
      bit writerSeen[int unsigned];
      int unsigned writerNode;
      int unsigned writerCnt;
      int unsigned wi;
      rec = lines[line];

      // Atomic results join the provenance set before any membership check.
      foreach (rec.writes[i])
        if (rec.writes[i].isAtomic && !rec.writes[i].cancelled)
          applyAtomicToSet(line, rec.writes[i]);

      sortWrites(rec);
      sortReads(rec);
      writerCnt = 0;
      writerNode = 0;
      foreach (rec.writes[i]) begin
        if (rec.writes[i].cancelled)
          continue;
        if (!writerSeen.exists(rec.writes[i].node)) begin
          writerSeen[rec.writes[i].node] = 1;
          writerNode = rec.writes[i].node;
          writerCnt++;
        end
      end

      // The exact walk: legal only when one node (or no node) ever wrote the
      // line. The image starts at the initialisation pattern and takes each
      // write in the writer's own request order.
      if (writerCnt <= 1) begin
        for (int unsigned i = 0; i < 64; i++)
          image[i] = bit'(initByte(line + chiAddrT'(i)));
        wi = 0;
        foreach (rec.reads[r]) begin
          topMemObs obs;
          obs = rec.reads[r];
          while ((wi < rec.writes.size()) &&
                 (rec.writes[wi].reqTime < obs.reqTime)) begin
            if (!rec.writes[wi].cancelled)
              applyWrite(image, rec.writes[wi]);
            wi++;
          end
          // With no writes at all every node's read must return the
          // initialisation pattern; with one writer only that writer's reads
          // are ordered against the writes soundly.
          if ((writerCnt == 0) || (obs.node == writerNode)) begin
            obs.exactChecked = 1'b1;
            readExactCount++;
            for (int unsigned i = 0; i < 64; i++) begin
              if (!obs.valid[i])
                continue;
              if ($isunknown(obs.bytes[i])) begin
                xErrorCount++;
                `uvm_error("MEM/X", $sformatf(
                  "line 'h%0h byte %0d: X on the data bus (node %0d read at %0t)",
                  line, i, obs.node, obs.t))
              end
              else if (bit'(obs.bytes[i]) !== image[i]) begin
                staleErrorCount++;
                `uvm_error("MEM/STALE", $sformatf(
                  "line 'h%0h byte %0d: node %0d read 'h%02x at %0t but the serialised content is 'h%02x (request at %0t)",
                  line, i, obs.node, bit'(obs.bytes[i]), obs.t, image[i],
                  obs.reqTime))
              end
            end
          end
        end
      end

      // Provenance for everything the exact walk did not judge.
      foreach (rec.reads[r])
        if (!rec.reads[r].exactChecked)
          checkObsBytes(rec.reads[r]);
      foreach (rec.others[o])
        checkObsBytes(rec.others[o]);
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("MEM/SUMMARY", $sformatf(
      "memory model: %0d lines, %0d writes (%0d atomics), %0d observations, %0d exact reads; %0d provenance / %0d stale / %0d transport / %0d X errors, %0d accept-all bytes",
      lines.num(), writeCount, atomicCount, obsCount, readExactCount,
      provenanceErrorCount, staleErrorCount, transportErrorCount, xErrorCount,
      acceptAllCount), UVM_MEDIUM)
  endfunction

endclass
