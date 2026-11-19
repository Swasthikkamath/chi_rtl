`ifndef CHIENV_INCLUDED
`define CHIENV_INCLUDED

class chiEnv extends uvm_env;
  `uvm_component_utils(chiEnv)

  chiRequestNodeAgent chiRequestNodeAgentHandle[];
  chiSubordinateNodeAgent chiSubordinateNodeAgentHandle[];
  chiEnvConfig chiEnvConfigHandle;

  extern function new(string name="chiEnv",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void connect_phase(uvm_phase phase);
endclass
function chiEnv::new(string name="chiEnv",uvm_component parent=null);
  super.new(name,parent);
endfunction

function void chiEnv::build_phase(uvm_phase phase);
  super.build_phase(phase);
  chiRequestNodeAgentHandle = new[chiEnvConfigHandle.numOfRequestNode];
  chiSubordinateNodeAgentHandle = new[chiEnvConfigHandle.numOfSubordinateNode];
  
  foreach(chiRequestNodeAgentHandle[i]) begin 
     chiRequestNodeAgentHandle[i] = chiRequestNodeAgent :: type_id ::create($sformatf("chiRequestNodeAgentHandle[%d]",i),this);
     chiRequestNodeAgentHandle[i].requestNodeId = i;
     uvm_config_db#(chiRequestNodeAgentConfig)::set(this,$sformatf("chiRequestNodeAgentHandle[%d]",i),$sformatf("chiRequestNodeAgentConfigHandle[%d]",i),chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i]);
  end 
  foreach(chiSubordinateNodeAgentHandle[i]) begin
     chiSubordinateNodeAgentHandle[i] = chiSubordinateNodeAgent :: type_id ::create($sformatf("chiSubordinateNodeAgentHandle[%d]",i),this);
     chiSubordinateNodeAgentHandle[i].subordinateNodeId = i;
     uvm_config_db#(chiSubordinateNodeAgentConfig)::set(this,$sformatf("chiSubordinateNodeAgentHandle[%d]",i),$sformatf("chiSubordinateNodeAgentConfigHandle[%d]",i),chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i]);
  end
endfunction
function void chiEnv::connect_phase(uvm_phase phase);
endfunction 

`endif 
