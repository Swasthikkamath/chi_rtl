//==============================================================================
// chiClkRstBfm
//
// Why this is a separate BFM rather than an initial block in hdlTop:
//
// The DUT drives CLK and RESETn onto every chi_if from its own clk/resetn
// inputs [ASSUMPTION:2], so the interface clock is an output of the design and
// the only clock source in the testbench is this BFM's drive of the two
// top-level ports. Every other BFM samples chiPort.CLK instead, which means
// this is the one place where the timebase is defined. Keeping it in an
// interface rather than in hdlTop lets a test change the period, hold reset
// longer, or issue a mid-test reset through a virtual handle, without hdlTop
// knowing anything about tests.
//
// No signal declared here has a declaration initialiser, because reset also
// assigns them; Xcelium treats an initialiser plus a reset assignment as two
// drivers on a variable in some elaboration modes.
//==============================================================================

interface chiClkRstBfm;

  import chiGlobalsPkg::*;

  // Default period and reset length. 10 cycles of reset satisfies the DUT,
  // which has no minimum, and releases reset on a clock edge because reset is
  // synchronous and active low throughout [ASSUMPTION:16].
  localparam time CLK_PERIOD_DEFAULT = 2ns;
  localparam int unsigned RESET_CYCLES_DEFAULT = 10;

  logic clk;
  logic resetn;

  time         clkPeriod;
  int unsigned resetCycles;
  bit          clkRunning;

  initial begin
    clk = 1'b0;
    resetn = 1'b0;
    clkPeriod = CLK_PERIOD_DEFAULT;
    resetCycles = RESET_CYCLES_DEFAULT;
    clkRunning = 1'b0;
  end

  // A single process owns clk, so a test that changes the period cannot create
  // a second driver.
  task automatic startClock(input time period = 0);
    if (period != 0) clkPeriod = period;
    if (clkRunning) return;
    clkRunning = 1'b1;
    fork
      forever begin
        #(clkPeriod / 2) clk = ~clk;
      end
    join_none
  endtask

  task automatic applyReset(input int unsigned cycles = 0);
    if (cycles != 0) resetCycles = cycles;
    resetn = 1'b0;
    repeat (resetCycles) @(posedge clk);
    resetn <= 1'b1;
    @(posedge clk);
  endtask

  task automatic waitClocks(input int unsigned cycles);
    repeat (cycles) @(posedge clk);
  endtask

  task automatic waitResetRelease();
    while (resetn !== 1'b1) @(posedge clk);
  endtask

  function automatic bit inReset();
    return resetn !== 1'b1;
  endfunction

endinterface : chiClkRstBfm
