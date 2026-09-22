// The backing store every Subordinate port answers from.
//
// One instance is shared by all SN-F and SN-I agents rather than one per
// port, and that is forced rather than convenient. The HN-F picks which
// Subordinate serves an address by hashing it, and the hash is inside the
// DUT, so a black-box testbench cannot say in advance which port a line will
// arrive on. A per-port store would report a miss the first time the DUT
// chose a different port than the testbench guessed. Keying by address
// across all ports removes the guess entirely. See OPEN QUESTIONS Q9.
//
// This is the store the DUT reads and writes. It is deliberately not the
// scoreboard's memory model: topMemoryRefModel keeps its own independent
// copy built from observed boundary traffic, so the two can disagree and the
// scoreboard can say so.

class chiSubordinateMemory extends uvm_object;
  // Sparse, line granular. Unwritten lines read as a per-line pattern rather
  // than zero, so a test that reads before writing still gets a value that
  // differs between lines and a mis-routed read is visible as wrong data
  // instead of a plausible zero.
  typedef struct {
    logic [7:0] byteVal [CACHE_LINE_BYTES];
    logic [7:0] poison;      // one bit per 64 bits of the line
    logic [3:0] tag [CACHE_LINE_BYTES/16];
    bit written;
  } chiMemLineT;

  chiMemLineT lines[chiAddrT];
  int unsigned readCount;
  int unsigned writeCount;

  `uvm_object_utils(chiSubordinateMemory)

  function new(string name = "chiSubordinateMemory");
    super.new(name);
    readCount = 0;
    writeCount = 0;
  endfunction

  function chiAddrT chiLineAddr(input chiAddrT addr);
    return lineAlign(addr);
  endfunction

  // The reset pattern for a line nobody has written. Derived from the line
  // address so every line differs and the value is reproducible across runs
  // and across the reference model.
  function logic [7:0] chiResetByte(input chiAddrT line, input int unsigned offset);
    return logic'(8'hA5) ^ logic'(line[15:8]) ^ logic'(line[7:0]) ^ logic'(8'(offset));
  endfunction

  function void chiEnsureLine(input chiAddrT line);
    chiMemLineT fresh;
    if (lines.exists(line))
      return;
    for (int unsigned b = 0; b < CACHE_LINE_BYTES; b++)
      fresh.byteVal[b] = chiResetByte(line, b);
    for (int unsigned t = 0; t < (CACHE_LINE_BYTES/16); t++)
      fresh.tag[t] = '0;
    fresh.poison = '0;
    fresh.written = 1'b0;
    lines[line] = fresh;
  endfunction

  // Read the whole 64-byte line as one wide value, which is the shape the
  // driver slices data flits out of.
  function logic [511:0] chiReadLine(input chiAddrT addr);
    chiAddrT line;
    logic [511:0] value;
    line = chiLineAddr(addr);
    chiEnsureLine(line);
    value = '0;
    for (int unsigned b = 0; b < CACHE_LINE_BYTES; b++)
      value[b*8 +: 8] = lines[line].byteVal[b];
    readCount++;
    return value;
  endfunction

  function logic [7:0] chiReadPoison(input chiAddrT addr);
    chiAddrT line;
    line = chiLineAddr(addr);
    chiEnsureLine(line);
    return lines[line].poison;
  endfunction

  // Apply one data flit. byteOffset is where this flit's data sits in the
  // line, which the caller derives from DataID rather than from arrival
  // order, because packets of a transfer may arrive in any order and later
  // ones may be elided outright. See OPEN QUESTIONS Q8.
  function void chiWriteBeat(
    input chiAddrT addr,
    input int unsigned byteOffset,
    input chiDataT data,
    input chiByteEnableT be,
    input logic [7:0] poison
  );
    chiAddrT line;
    int unsigned slot;
    line = chiLineAddr(addr);
    chiEnsureLine(line);
    for (int unsigned b = 0; b < BE_W; b++) begin
      slot = byteOffset + b;
      if (slot >= CACHE_LINE_BYTES)
        continue;
      if (be[b])
        lines[line].byteVal[slot] = data[b*8 +: 8];
    end
    if (POISON_EN) begin
      for (int unsigned p = 0; p < 8; p++) begin
        slot = byteOffset + (p * 8);
        if (slot >= CACHE_LINE_BYTES)
          continue;
        if (poison[p])
          lines[line].poison[slot/8] = 1'b1;
      end
    end
    lines[line].written = 1'b1;
    writeCount++;
  endfunction

  // WriteNoSnpZero transfers no data at all, so the Subordinate zeroes the
  // line on the strength of the request alone.
  // [SPEC:IHI0050H B2.3.9.3 Home to Subordinate Write Zero transactions]
  function void chiWriteZero(input chiAddrT addr);
    chiAddrT line;
    line = chiLineAddr(addr);
    chiEnsureLine(line);
    for (int unsigned b = 0; b < CACHE_LINE_BYTES; b++)
      lines[line].byteVal[b] = '0;
    lines[line].poison = '0;
    lines[line].written = 1'b1;
    writeCount++;
  endfunction

  // Backdoor seed, for tests that want a known value without spending a
  // transaction to put it there.
  function void chiPreloadLine(input chiAddrT addr, input logic [511:0] value);
    chiAddrT line;
    line = chiLineAddr(addr);
    chiEnsureLine(line);
    for (int unsigned b = 0; b < CACHE_LINE_BYTES; b++)
      lines[line].byteVal[b] = value[b*8 +: 8];
    lines[line].written = 1'b1;
  endfunction

  function int unsigned chiLineCount();
    return lines.size();
  endfunction
endclass
