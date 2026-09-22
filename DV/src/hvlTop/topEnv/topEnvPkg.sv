// Integration layer. The four reference models, the scoreboard, and
// the agent environment live here. Included files stay in dependency
// order. Sinks name topScoreboard before that class is defined, which
// the typedef below permits.

package topEnvPkg;
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  import chiRequesterPkg::*;
  import chiSubordinatePkg::*;
  `include "uvm_macros.svh"

  typedef class topScoreboard;

  `include "topEnvConfig.sv"
  `include "topLinkModel.sv"
  `include "topLifecycleModel.sv"
  `include "topDirectoryModel.sv"
  `include "topMemoryModel.sv"
  `include "topCoverage.sv"
  `include "topReqSink.sv"
  `include "topRspSink.sv"
  `include "topDatSink.sv"
  `include "topSnpSink.sv"
  `include "topLinkSink.sv"
  `include "topFlitSink.sv"
  `include "topScoreboard.sv"
  `include "chiVirtualSequencer.sv"
  `include "chiEnv.sv"
  `include "topEnv.sv"
endpackage
