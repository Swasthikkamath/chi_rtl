// Requester agent package.
//
// The include order is the dependency order: the transaction and the
// configuration are needed by everything, the cache model by the driver, and
// the agent by nothing inside the package.
package chiRequesterPkg;
  import uvm_pkg::*;
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  `include "uvm_macros.svh"

  `include "chiRequesterTx.sv"
  `include "chiRequesterAgentConfig.sv"
  `include "chiRequesterCacheModel.sv"
  `include "chiRequesterSequencer.sv"
  `include "chiRequesterDriverProxy.sv"
  `include "chiRequesterMonitorProxy.sv"
  `include "chiRequesterCoverage.sv"
  `include "chiRequesterAgent.sv"
  `include "chiRequesterSequences.sv"
endpackage
