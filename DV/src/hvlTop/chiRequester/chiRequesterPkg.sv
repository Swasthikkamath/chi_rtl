// Requester HVL. Sequences describe intent; chiRequesterDriverProxy
// turns that into flits using chiRequesterCacheModel. Included files
// stay in dependency order. Pin traffic goes through the virtual BFM
// published by hdlTop.

package chiRequesterPkg;
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned CHI_TB_OUTSTANDING_CAP = 16;

  `include "chiRequesterConfig.sv"
  `include "chiRequesterTx.sv"
  `include "chiRequesterCacheModel.sv"
  `include "chiRequesterTxnContext.sv"
  `include "chiRequesterSequencer.sv"
  `include "chiRequesterCoverage.sv"
  `include "chiRequesterDriverProxy.sv"
  `include "chiRequesterMonitorProxy.sv"
  `include "chiRequesterAgent.sv"
  `include "chiRequesterSeq.sv"
endpackage
