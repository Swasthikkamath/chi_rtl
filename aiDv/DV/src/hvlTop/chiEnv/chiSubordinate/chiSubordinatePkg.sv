// Subordinate agent package.
package chiSubordinatePkg;
  import uvm_pkg::*;
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  `include "uvm_macros.svh"

  `include "chiSubordinateTx.sv"
  `include "chiSubordinateAgentConfig.sv"
  `include "chiSubordinateMemoryModel.sv"
  `include "chiSubordinateSequencer.sv"
  `include "chiSubordinateDriverProxy.sv"
  `include "chiSubordinateMonitorProxy.sv"
  `include "chiSubordinateCoverage.sv"
  `include "chiSubordinateAgent.sv"
  `include "chiSubordinateSequences.sv"
endpackage
