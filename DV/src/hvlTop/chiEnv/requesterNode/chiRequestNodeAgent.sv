`ifndef CHIREQUESTNODEAGENT_INCLUDED 
`define CHIREQUESTNODEAGENT_INCLUDED

class chiRequestNodeAgent extends uvm_agent;
  `uvm_component_utils(chiRequestNodeAgent) //may be we can think of automation of certain object or config property
  int requestNodeId;
  chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle;
  extern function new(string name="chiRequestNodeAgent",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);
  
endclass

function chiRequestNodeAgent :: new(string name="chiRequestNodeAgent",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiRequestNodeAgent::build_phase(uvm_phase phase);
  super.build_phase(phase); //this call is optional
  if(!(uvm_config_db#(chiRequestNodeAgentConfig) :: get(this,"",$sformatf("chiRequestNodeAgentConfigHandle[%d]",requestNodeId),chiRequestNodeAgentConfigHandle))) begin
    `uvm_fatal("SUBORDINATE AGENT","AGENT NOT CONFIGURED")
  end  
endfunction 

function void chiRequestNodeAgent::connect_phase(uvm_phase phase);
endfunction 

`endif 
