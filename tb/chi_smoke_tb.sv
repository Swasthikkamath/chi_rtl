// Reset, link bring-up and idle smoke test.
//
// This is not a protocol testbench. It exists so that the design is actually
// executed rather than only elaborated, which lint cannot do. Three things
// are checked: the elaboration checks in chi_cfg_check pass, every link
// reaches RUN in both directions and exchanges its full L-Credit allocation,
// and an idle fabric with live links stays silent.
//
// The last check is only meaningful because the links are up. With no node
// model the receive links never leave STOP, no credits are issued, and a
// silent fabric proves nothing.
module chi_smoke_tb;
  localparam chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT;
  localparam int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn;
  localparam int unsigned NUM_EXTERNAL =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni;

  localparam int unsigned RESET_CYCLES = 8;
  // Long enough for both link directions to walk STOP, ACTIVATE, RUN and for
  // every channel to hand over its whole credit allocation.
  localparam int unsigned BRINGUP_CYCLES = 64;
  localparam int unsigned RUN_CYCLES = 512;

  logic clk;
  logic resetn;
  logic [31:0] PRDATA;
  logic PREADY;
  logic PSLVERR;
  logic [NUM_NODES-1:0] linkUp;
  logic [NUM_NODES-1:0] linkParityError;
  logic [NUM_NODES-1:0] linkCreditError;
  logic [NUM_EXTERNAL-1:0] nodeLinkRun;
  logic [NUM_EXTERNAL-1:0] nodeCreditsFull;
  logic [NUM_EXTERNAL-1:0] nodeFlitSeen;

  chi_sim_harness #(.CFG(CFG)) dut (
    .clk(clk),
    .resetn(resetn),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .linkUp(linkUp),
    .linkParityError(linkParityError),
    .linkCreditError(linkCreditError),
    .nodeLinkRun(nodeLinkRun),
    .nodeCreditsFull(nodeCreditsFull),
    .nodeFlitSeen(nodeFlitSeen)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    resetn = 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    resetn = 1'b1;

    repeat (BRINGUP_CYCLES) @(posedge clk);
    if (nodeLinkRun !== {NUM_EXTERNAL{1'b1}})
      $fatal(1, "Node side of the link is not running: %b", nodeLinkRun);
    if (linkUp[NUM_EXTERNAL-1:0] !== {NUM_EXTERNAL{1'b1}})
      $fatal(1, "Interconnect side of the link is not running: %b",
             linkUp[NUM_EXTERNAL-1:0]);
    // HN-F, HN-I and MN are internal endpoints with no external link.
    if (linkUp[NUM_NODES-1:NUM_EXTERNAL] !== '0)
      $fatal(1, "An internal endpoint reported a link: %b",
             linkUp[NUM_NODES-1:NUM_EXTERNAL]);
    if (nodeCreditsFull !== {NUM_EXTERNAL{1'b1}})
      $fatal(1, "L-Credits were not fully issued: %b", nodeCreditsFull);
    $display("chi_smoke_tb: %0d links up with full credits after %0d cycles",
             NUM_EXTERNAL, BRINGUP_CYCLES);

    repeat (RUN_CYCLES) @(posedge clk);
    if (|linkParityError)
      $fatal(1, "Idle fabric reported a flit parity error: %b",
             linkParityError);
    if (|linkCreditError)
      $fatal(1, "Idle fabric reported an L-Credit error: %b",
             linkCreditError);
    if (|nodeFlitSeen)
      $fatal(1, "Idle fabric delivered a flit to a node: %b", nodeFlitSeen);
    if (nodeLinkRun !== {NUM_EXTERNAL{1'b1}})
      $fatal(1, "A link dropped out of RUN while idle: %b", nodeLinkRun);
    $display("chi_smoke_tb: passed %0d reset and %0d idle cycles",
             RESET_CYCLES, RUN_CYCLES);
    $finish;
  end
endmodule
