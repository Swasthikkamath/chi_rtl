// Subordinate HVL. A sequence only sets response policy. Requests are
// whatever arrives on REQ, and chiSubordinateDriverProxy answers them
// from chiSubordinateMemoryModel. Included files stay in dependency
// order. Pin traffic goes through the virtual BFM published by hdlTop.
// [ASSUMPTION:4] [TOP:reqToNoc]

package chiSubordinatePkg;
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  `include "uvm_macros.svh"

  localparam int unsigned CHI_TB_OUTSTANDING_CAP = 16;

  `include "chiSubordinateConfig.sv"
  `include "chiSubordinateTx.sv"
  `include "chiSubordinateMemoryModel.sv"
  `include "chiSubordinateTxnContext.sv"
  `include "chiSubordinateSequencer.sv"
  `include "chiSubordinateCoverage.sv"
  `include "chiSubordinateDriverProxy.sv"
  `include "chiSubordinateMonitorProxy.sv"
  `include "chiSubordinateAgent.sv"
  `include "chiSubordinateSeq.sv"
endpackage
