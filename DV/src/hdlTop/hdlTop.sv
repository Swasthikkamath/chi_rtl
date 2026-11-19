`ifndef HDLTOP_INCLUDED
`define HDLTOP_INCLUDED

module hdlTop;
  timeunit 1ns;
  timeprecision 1ps;

  import chiGlobalsPkg::*;

  bit clk;
  bit reset;

  always #5 clk = ~clk;
  chiInterface chiRequestNodeInterfaceHandle[NUMOFREQUESTNODE](clk,reset);
  chiInterface chiSubordinateNodeInterfaceHandle[NUMOFSUBORDINATENODE](clk,reset);

  //connect to rtl (map the index to configured rn or sn type and connect the
  //ports accordingly 
  //
  genvar i;
  generate
    for(i=0;i<NUMOFREQUESTNODE;i++) begin 
      chiRequestNodeAgentBfm#(i) chiRequestNodeAgentBfmHandle(chiRequestNodeInterfaceHandle[i]);
    end 
  endgenerate 

  genvar j;
  generate
    for(j=0;j<NUMOFSUBORDINATENODE;j++) begin
      chiSubordinateNodeAgentBfm#(j) chiSubordinateNodeAgentBfmHandle(chiSubordinateNodeInterfaceHandle[j]);
    end
  endgenerate
endmodule 
`endif 
