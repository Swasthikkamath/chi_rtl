`ifndef HVLTOP_INCLUDED
`define HVLTOP_INCLUDED

module hvlTop;
  timeunit  1ns;
  timeprecision 1ps;
  import chiTestPkg::*;
  import uvm_pkg::*;


  initial begin 
    run_test("chiBaseTest");
  end 
endmodule 
`endif 



