// Reset and idle smoke test.
//
// This is not a protocol testbench. It exists so that the elaboration checks
// in chi_cfg_check and every bound assertion are actually executed rather
// than only elaborated: it holds reset, releases it, and runs the idle
// fabric. Any elaboration $fatal, any assertion that fires out of reset, and
// any X propagation into a checked expression fails the run.
module chi_smoke_tb;
  localparam chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT;
  localparam int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn;

  localparam int unsigned RESET_CYCLES = 8;
  localparam int unsigned RUN_CYCLES = 512;

  logic clk;
  logic resetn;
  logic [31:0] PRDATA;
  logic PREADY;
  logic PSLVERR;
  logic [NUM_NODES-1:0] linkUp;
  logic [NUM_NODES-1:0] linkParityError;
  logic [NUM_NODES-1:0] linkCreditError;

  chi_interconnect_compile dut (
    .clk(clk),
    .resetn(resetn),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .linkUp(linkUp),
    .linkParityError(linkParityError),
    .linkCreditError(linkCreditError)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    resetn = 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    resetn = 1'b1;
    repeat (RUN_CYCLES) @(posedge clk);
    if (|linkParityError)
      $fatal(1, "Idle fabric reported a flit parity error");
    if (|linkCreditError)
      $fatal(1, "Idle fabric reported an L-Credit error");
    $display("chi_smoke_tb: passed %0d reset and %0d run cycles",
             RESET_CYCLES, RUN_CYCLES);
    $finish;
  end

  // An idle fabric must never present a flit on any node-facing channel.
  always @(posedge clk) begin
    if (resetn) begin
      if (dut.rnfIf[0].RXSNPFLITV)
        $fatal(1, "Idle fabric drove a snoop flit");
      if (dut.snfIf[0].RXREQFLITV)
        $fatal(1, "Idle fabric drove a downstream request flit");
    end
  end
endmodule
