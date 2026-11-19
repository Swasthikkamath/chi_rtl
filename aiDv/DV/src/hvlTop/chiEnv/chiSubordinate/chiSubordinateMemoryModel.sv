// Memory behind one Subordinate.
//
// Sparse and byte addressed: a location that has never been written reads as
// memInitByte of its address. That function is shared with the scoreboard's
// reference copy, which is the point of it. The two models are never loaded
// from a common image and never exchange contents; they each derive the same
// byte from the address independently, so when a read returns the wrong data
// it means the fabric moved the wrong bytes, not that two models were
// initialised differently.
class chiSubordinateMemoryModel extends uvm_object;

  protected chiByteT mem [chiAddrT];

  protected int unsigned readCount;
  protected int unsigned writeCount;

  `uvm_object_utils(chiSubordinateMemoryModel)

  function new(string name = "chiSubordinateMemoryModel");
    super.new(name);
  endfunction

  function chiByteT readByte(chiAddrT addr);
    if (!mem.exists(addr)) return memInitByte(addr);
    return mem[addr];
  endfunction

  function void writeByte(chiAddrT addr, chiByteT value);
    mem[addr] = value;
  endfunction

  // A whole cache line, which is the only granularity Stage 1 moves.
  function chiLineBytesT readLine(chiAddrT addr);
    chiLineBytesT bytes;
    chiAddrT      base;
    base = lineBaseOf(addr);
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++)
      bytes[i] = readByte(base + i);
    readCount++;
    return bytes;
  endfunction

  function void writeLine(chiAddrT addr, chiLineBytesT bytes);
    chiAddrT base;
    base = lineBaseOf(addr);
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++)
      writeByte(base + i, bytes[i]);
    writeCount++;
  endfunction

  // Byte-enable aware write, for a partial write that must leave the bytes it
  // does not name untouched [SPEC:IHI0050H B2.9.2].
  function void writeLineMasked(chiAddrT addr, chiLineBytesT bytes,
                                logic [CHI_LINE_BYTES-1:0] byteEnable);
    chiAddrT base;
    base = lineBaseOf(addr);
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++)
      if (byteEnable[i]) writeByte(base + i, bytes[i]);
    writeCount++;
  endfunction

  function string convert2string();
    return $sformatf("memory: %0d bytes written, %0d line reads, %0d line writes",
                     mem.num(), readCount, writeCount);
  endfunction
endclass
