`ifndef CHIENVCONFIG_INCLUDED
`define CHIENVCONFIG_INCLUDED

class chiEnvConfig extends uvm_object;
  `uvm_object_utils(chiEnvConfig)

  extern function new(string name="chiEnvConfig");

  int numOfRequestNode,numOfSubordinateNode;
  bit hasScoreboard=1;
  chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle[];
  chiSubordinateNodeAgentConfig chiSubordinateNodeAgentConfigHandle[];
endclass
function chiEnvConfig::new(string name="chiEnvConfig");
  super.new(name);
endfunction

`endif
