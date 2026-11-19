`ifndef CHIENVPKG_INCLUDED
`define CHIENVPKG_INCLUDED


package chiEnvPkg;
  `include"uvm_macros.svh"
  import uvm_pkg::*;
  
  import chiRequestNodePkg::*;
  import chiSubordinateNodePkg::*;

  `include"chiEnvConfig.sv"
  `include"chiEnv.sv"


endpackage
`endif
