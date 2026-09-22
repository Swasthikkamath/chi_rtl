// chiClkRstBfm drives only the interconnect's clk and resetn ports.
// chi_if.CLK and chi_if.RESETn are DUT outputs. BFMs sample those,
// so this interface must not drive them. See OPEN QUESTIONS item 2.
// [TOP:clk] [TOP:resetn] [ASSUMPTION:2]

`timescale 1ns/1ps

interface chiClkRstBfm;
  logic clk;
  logic resetn;

  localparam int unsigned CHI_TB_CLK_HALF_PERIOD = 5;
  // [ASSUMPTION:16] Hold reset for at least ten cycles.
  localparam int unsigned CHI_TB_RESET_CYCLES = 10;

  initial begin
    clk = 1'b0;
    resetn = 1'b0;
    repeat (CHI_TB_RESET_CYCLES) @(posedge clk);
    resetn = 1'b1;
  end

  always #(CHI_TB_CLK_HALF_PERIOD) clk = ~clk;

  task automatic chiWaitResetRelease();
    wait (resetn === 1'b1);
  endtask
endinterface
