`ifndef CHISUBORDINATENODEPKG_INCLUDED
`define CHISUBORDINATENODEPKG_INCLUDED

package chiSubordinateNodePkg;

  `include "uvm_macros.svh"
  import uvm_pkg ::*;
  import chiGlobalsPkg::*;

  `include "chiSubordinateNodeTx.sv"
  `include "chiSubordinateNodeAgentConfig.sv"
  `include "chiSubordinateNodeLocalProcessor.sv"
  `include "chiSubordinateNodeSeqItemConverter.sv"
  `include "chiSubordinateNodeCfgConverter.sv"
  `include "chiSubordinateNodeSequencer.sv"
  `include "chiSubordinateNodeDriverProxy.sv"
  `include "chiSubordinateNodeMonitorProxy.sv"
  `include "chiSubordinateNodeAgent.sv"    
endpackage 
`endif
