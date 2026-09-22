// HVL top. The only import is the test package, which re-exports
// uvm_pkg so run_test is visible here. No class in this module
// touches a pin.

module hvlTop;
  // chiTestPkg re-exports uvm_pkg. slang does not make that export
  // visible through a single import, so uvm_pkg is imported here too.
  import uvm_pkg::*;
  import chiTestPkg::*;
  initial run_test();
endmodule
