// Top-level environment HVL. topEnv builds one agent per configured
// external port from the two agent packages, and the scoreboard feeds the
// four reference models [ASSUMPTION:18] from the raw monitor sample
// streams. Included files stay in dependency order: the config, then the
// models, then the scoreboard that owns them, then the env.

package topEnvPkg;
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  import chiRequesterPkg::*;
  import chiSubordinatePkg::*;
  `include "uvm_macros.svh"

  `include "topEnvConfig.sv"
  `include "topLinkModel.sv"
  `include "topLifecycleModel.sv"
  `include "topDirectoryModel.sv"
  `include "topMemoryModel.sv"
  `include "topScoreboard.sv"
  `include "topEnv.sv"
endpackage
