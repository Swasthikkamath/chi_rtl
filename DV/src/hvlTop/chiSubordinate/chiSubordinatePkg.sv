// Subordinate HVL. Unlike the requester, nothing here originates traffic:
// the driver proxy answers what the interconnect sends it, and sequences
// only shape those answers. Included files stay in dependency order. Pin
// traffic goes through the virtual BFM published by hdlTop.

package chiSubordinatePkg;
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  `include "uvm_macros.svh"

  // How many requests one Subordinate port works on at once. Smaller than
  // the requester cap because the only backpressure a Subordinate has is to
  // stop granting credits, and a cap this size makes that reachable in a
  // short test rather than only under sustained load.
  localparam int unsigned CHI_TB_SN_OUTSTANDING_CAP = 8;

  `include "chiSubordinateConfig.sv"
  `include "chiSubordinateMemory.sv"
  `include "chiSubordinateTx.sv"
  `include "chiSubordinateTxnContext.sv"
  `include "chiSubordinateSequencer.sv"
  `include "chiSubordinateCoverage.sv"
  `include "chiSubordinateDriverProxy.sv"
  `include "chiSubordinateMonitorProxy.sv"
  `include "chiSubordinateAgent.sv"
  `include "chiSubordinateSeq.sv"
endpackage
