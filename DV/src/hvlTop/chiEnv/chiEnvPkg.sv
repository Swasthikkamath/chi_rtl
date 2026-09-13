// CHI environment package.
package chiEnvPkg;
  import uvm_pkg::*;
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;
  import chiRequesterPkg::*;
  import chiSubordinatePkg::*;

  `include "uvm_macros.svh"

  `include "chiEnvConfig.sv"
  `include "chiVirtualSequencer.sv"
  `include "chiEnv.sv"
  `include "chiVirtualSequences.sv"
endpackage
