// Clock and reset for the whole testbench.
//
// The fabric is a single clock domain: every chi_if takes the same CLK and
// RESETn, and the DUT's own top takes one clk and one resetn for all ports
// [top/chi_interconnect_top.sv]. There is therefore one generator rather than
// one per agent.
//
// Reset is asserted from time zero and released a fixed number of cycles
// later. Nothing in the testbench may drive a flit before that happens, which
// the agents enforce by waiting for RESETn in their own bring-up.
interface chiClkRstBfm #(
  parameter time CLK_PERIOD   = 10ns,
  parameter int unsigned RESET_CYCLES = 8
);
  bit clk    = 1'b0;
  bit resetn = 1'b0;

  initial forever #(CLK_PERIOD / 2) clk = ~clk;

  initial begin
    resetn = 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    resetn = 1'b1;
  end

  task automatic waitResetDone();
    if (!resetn) @(posedge resetn);
    @(posedge clk);
  endtask

  task automatic waitCycles(input int unsigned count);
    repeat (count) @(posedge clk);
  endtask
endinterface
