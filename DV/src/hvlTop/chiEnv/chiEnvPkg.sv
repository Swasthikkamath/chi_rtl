`ifndef CHIENVPKG_INCLUDED
`define CHIENVPKG_INCLUDED


package chiEnvPkg;
  `include "uvm_macros.svh"
  import uvm_pkg::*;
  
  import chiRequestNodePkg::*;
  import chiSubordinateNodePkg::*;
  import chiGlobalsPkg::*;
  `include "chiEnvConfig.sv"
  `include "chiScoreboard.sv"
  `include "chiEnv.sv"


endpackage
`endif
