// Dynamic side of the testbench.
//
// hdlTop owns the DUT and the pin-level BFMs and publishes a virtual interface
// handle for each of them. This module only starts UVM; the test named on the
// command line picks up those handles through the configuration database. The
// two tops are kept separate so that the static hierarchy elaborates whether
// or not a UVM test is running, which is what makes a pure elaboration check
// of the HDL side possible.
module hvlTop;
  import uvm_pkg::*;
  import chiTestPkg::*;

  initial begin
    run_test();
  end
endmodule
