// Sparse byte memory for one subordinate port. A byte that has never
// been written comes from chiMemInitData, so a later scoreboard can
// agree on that value without sharing this object. Region attributes
// are not applied here: the interconnect already delivered the request.
// [ASSUMPTION:8] [ASSUMPTION:10] [SPEC:IHI0050H B4.2]

class chiSubordinateMemoryModel extends uvm_object;
  logic [7:0] byteMem[chiAddrT];

  `uvm_object_utils(chiSubordinateMemoryModel)

  function new(string name = "chiSubordinateMemoryModel");
    super.new(name);
  endfunction

  function logic [63:0] chiLowMask(input int unsigned nbytes);
    if (nbytes >= 8)
      return {64{1'b1}};
    return (64'b1 << (nbytes * 8)) - 64'b1;
  endfunction

  function logic [7:0] chiByteAt(input chiAddrT addr);
    logic [63:0] word;
    chiAddrT aligned;
    if (byteMem.exists(addr))
      return byteMem[addr];
    aligned = addr & ~chiAddrT'(7);
    word = chiMemInitData(aligned);
    return word[(addr[2:0] * 8) +: 8];
  endfunction

  function logic [63:0] chiReadBytes(input chiAddrT addr, input int unsigned nbytes);
    logic [63:0] value;
    int unsigned count;
    value = '0;
    count = nbytes;
    if (count > 8)
      count = 8;
    for (int unsigned i = 0; i < count; i++)
      value[(i * 8) +: 8] = chiByteAt(addr + i);
    return value;
  endfunction

  function void chiWriteBytes(
    input chiAddrT addr,
    input logic [63:0] value,
    input int unsigned nbytes
  );
    int unsigned count;
    count = nbytes;
    if (count > 8)
      count = 8;
    for (int unsigned i = 0; i < count; i++)
      byteMem[addr + i] = value[(i * 8) +: 8];
  endfunction

  function void chiFillBytes(
    input chiAddrT addr,
    input int unsigned nbytes,
    input logic [7:0] value
  );
    for (int unsigned i = 0; i < nbytes; i++)
      byteMem[addr + i] = value;
  endfunction

  function void chiMergeLine(
    input chiAddrT line,
    input logic [511:0] data,
    input logic [63:0] be
  );
    for (int unsigned i = 0; i < CACHE_LINE_BYTES; i++)
      if (be[i])
        byteMem[line + i] = data[(i * 8) +: 8];
  endfunction

  function logic [63:0] chiInboundSlice(
    input logic [127:0] inbound,
    input int unsigned bitOffset
  );
    logic [63:0] value;
    value = '0;
    for (int unsigned bitIndex = 0; bitIndex < 64; bitIndex++)
      if ((bitOffset + bitIndex) < 128)
        value[bitIndex] = inbound[bitOffset + bitIndex];
    return value;
  endfunction

  function logic [63:0] chiSmax(
    input logic [63:0] left,
    input logic [63:0] right,
    input int unsigned nbytes
  );
    logic [63:0] a;
    logic [63:0] b;
    bit aNeg;
    bit bNeg;
    int unsigned signBit;
    a = left & chiLowMask(nbytes);
    b = right & chiLowMask(nbytes);
    if (nbytes >= 8) begin
      if ($signed(a) >= $signed(b))
        return a;
      return b;
    end
    signBit = (nbytes * 8) - 1;
    aNeg = a[signBit];
    bNeg = b[signBit];
    if (aNeg != bNeg)
      return aNeg ? b : a;
    if (a >= b)
      return a;
    return b;
  endfunction

  function logic [63:0] chiSmin(
    input logic [63:0] left,
    input logic [63:0] right,
    input int unsigned nbytes
  );
    logic [63:0] a;
    logic [63:0] b;
    bit aNeg;
    bit bNeg;
    int unsigned signBit;
    a = left & chiLowMask(nbytes);
    b = right & chiLowMask(nbytes);
    if (nbytes >= 8) begin
      if ($signed(a) <= $signed(b))
        return a;
      return b;
    end
    signBit = (nbytes * 8) - 1;
    aNeg = a[signBit];
    bNeg = b[signBit];
    if (aNeg != bNeg)
      return aNeg ? a : b;
    if (a <= b)
      return a;
    return b;
  endfunction

  // Load, swap and compare return the old value. Store writes the
  // result and the caller sends no data. Compare writes the swap
  // operand only when the old value matches. Little-endian, masked to
  // the operand width. [SPEC:IHI0050H B13.8] [ASSUMPTION:15]
  function logic [63:0] chiAtomic(
    input chiReqOpcodeE opcode,
    input chiAddrT addr,
    input int unsigned nbytes,
    input logic [127:0] inbound
  );
    logic [63:0] mask;
    logic [63:0] oldv;
    logic [63:0] operand;
    logic [63:0] swapv;
    logic [63:0] result;
    int unsigned width;
    width = nbytes;
    if (width == 0)
      width = 1;
    if (width > 8)
      width = 8;
    mask = chiLowMask(width);
    oldv = chiReadBytes(addr, width) & mask;
    operand = chiInboundSlice(inbound, 0) & mask;
    swapv = chiInboundSlice(inbound, width * 8) & mask;
    result = oldv;
    case (opcode)
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_STORE_ADD: result = (oldv + operand) & mask;
      REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_STORE_CLR: result = (oldv & ~operand) & mask;
      REQ_ATOMIC_LOAD_EOR, REQ_ATOMIC_STORE_EOR: result = (oldv ^ operand) & mask;
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_STORE_SET: result = (oldv | operand) & mask;
      REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_STORE_SMAX: result = chiSmax(oldv, operand, width);
      REQ_ATOMIC_LOAD_SMIN, REQ_ATOMIC_STORE_SMIN: result = chiSmin(oldv, operand, width);
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_STORE_UMAX: result = (oldv >= operand) ? oldv : operand;
      REQ_ATOMIC_LOAD_UMIN, REQ_ATOMIC_STORE_UMIN: result = (oldv <= operand) ? oldv : operand;
      REQ_ATOMIC_SWAP: result = operand;
      REQ_ATOMIC_COMPARE: result = (oldv == operand) ? swapv : oldv;
      default: result = oldv;
    endcase
    chiWriteBytes(addr, result, width);
    return oldv;
  endfunction
endclass
