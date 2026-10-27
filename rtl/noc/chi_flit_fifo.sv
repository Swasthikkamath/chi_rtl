// Registered output stage for a protocol endpoint.
//
// An endpoint pushes a flit when the FIFO has room and the fabric pops it when
// ready. outValid and outFlit come from the FIFO, and pushReady depends only on
// the occupancy, so neither direction of the handshake sees the other
// combinationally (design specification, Section 2.8). Two entries let one
// source stream at a flit per cycle.
module chi_flit_fifo #(
  parameter int unsigned DEPTH = 2,
  parameter int unsigned COUNT_W = $clog2(DEPTH + 1)
) (
  input  logic                   clk,
  input  logic                   resetn,
  input  logic                   pushValid,
  output logic                   pushReady,
  input  chi_pkg::chi_noc_flit_t pushFlit,
  output logic                   outValid,
  input  logic                   outReady,
  output chi_pkg::chi_noc_flit_t outFlit,
  output logic [COUNT_W-1:0]     count
);
  localparam int unsigned PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;

  chi_pkg::chi_noc_flit_t storage [DEPTH];
  logic [PTR_W-1:0] readPointer;
  logic [PTR_W-1:0] writePointer;
  logic push;
  logic pop;

  always_comb begin
    pushReady = int'(count) < DEPTH;
    outValid = count != '0;
    outFlit = storage[readPointer];
    push = pushValid && pushReady;
    pop = outValid && outReady;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      count <= '0;
      readPointer <= '0;
      writePointer <= '0;
      for (int unsigned entry = 0; entry < DEPTH; entry++)
        storage[entry] <= '0;
    end else begin
      if (push) begin
        storage[writePointer] <= pushFlit;
        writePointer <= (int'(writePointer) == (DEPTH - 1))
                        ? '0 : (writePointer + 1'b1);
      end
      if (pop)
        readPointer <= (int'(readPointer) == (DEPTH - 1))
                       ? '0 : (readPointer + 1'b1);
      if (push && !pop)
        count <= count + 1'b1;
      else if (!push && pop)
        count <= count - 1'b1;
    end
  end
endmodule
