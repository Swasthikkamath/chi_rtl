`ifndef CHISUBORDINATENODEAGENT_INCLUDED 
`define CHISUBORDINATENODEAGENT_INCLUDED

class chiSubordinateNodeAgent extends uvm_agent;
  `uvm_component_utils(chiSubordinateNodeAgent) //may be we can think of automation of certain object or config property
  int subordinateNodeId;
  chiSubordinateNodeAgentConfig chiSubordinateNodeAgentConfigHandle;
  extern function new(string name="chiSubordinateNodeAgent",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);
  
endclass

function chiSubordinateNodeAgent :: new(string name="chiSubordinateNodeAgent",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiSubordinateNodeAgent::build_phase(uvm_phase phase);
  super.build_phase(phase); //this call is optional 
  if(!(uvm_config_db#(chiSubordinateNodeAgentConfig) :: get(this,"",$sformatf("chiSubordinateNodeAgentConfigHandle[%d]",subordinateNodeId),chiSubordinateNodeAgentConfigHandle))) begin
    `uvm_fatal("SUBORDINATE AGENT","AGENT NOT CONFIGURED")
  end 
endfunction 

function void chiSubordinateNodeAgent::connect_phase(uvm_phase phase);
endfunction 

`endif 
