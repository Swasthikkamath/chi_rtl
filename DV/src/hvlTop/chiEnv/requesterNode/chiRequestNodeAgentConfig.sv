`ifndef CHIREQUESTNODEAGENTCONFIG_INCLUDED
`define CHIREQUESTNODEAGENTCONFIG_INCLUDED

class chiRequestNodeAgentConfig extends uvm_object;
  `uvm_object_utils(chiRequestNodeAgentConfig)
  int localProcessorCount=3;
  requestNodeTypeEnum requestNodeTypeEnumHandle;
  uvm_active_passive_enum is_active;
  requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle[];
  //should plan for other config property   
  extern function new(string name="chiRequestNodeAgentConfig");
endclass

function chiRequestNodeAgentConfig :: new(string name="chiRequestNodeAgentConfig");
  super.new(name);
endfunction 
`endif 
