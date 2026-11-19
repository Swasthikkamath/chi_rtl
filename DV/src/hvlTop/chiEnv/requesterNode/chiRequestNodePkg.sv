`ifndef CHIREQUESTNODEPKG_INCLUDED
`define CHIREQUESTNODEPKG_INCLUDED

package chiRequestNodePkg;

  `include "uvm_macros.svh"
  import uvm_pkg ::*;
  import chiGlobalsPkg::*;

  `include "chiRequestNodeTx.sv"
  `include "chiRequestNodeLocalProcessorConfig.sv"
  `include "chiRequestNodeAgentConfig.sv"
  `include "chiRequestNodeLocalProcessor.sv"
  `include "chiRequestNodeSeqItemConverter.sv"
  `include "chiRequestNodeCfgConverter.sv"
  `include "chiRequestNodeSequencer.sv"
  `include "chiRequestNodeDriverProxy.sv"
  `include "chiRequestNodeMonitorProxy.sv"
  `include "chiRequestNodeAgent.sv"    
endpackage 
`endif
