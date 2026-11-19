`ifndef CHITESTPKG_INCLUDED
`define CHITESTPKG_INCLUDED


package chiTestPkg;
  `include"uvm_macros.svh"
  import uvm_pkg ::*;
  import chiEnvPkg::*;
  import chiGlobalsPkg::*;
  import chiRequestNodePkg::*;
  import chiSubordinateNodePkg::*;
  `include "chiBaseTest.sv"
endpackage 

`endif 
