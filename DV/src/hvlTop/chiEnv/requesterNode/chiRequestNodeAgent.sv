`ifndef CHIREQUESTNODEAGENT_INCLUDED 
`define CHIREQUESTNODEAGENT_INCLUDED

class chiRequestNodeAgent extends uvm_agent;
  `uvm_component_utils(chiRequestNodeAgent) //may be we can think of automation of certain object or config property
  int requestNodeId;
  chiRequestNodeDriverProxy chiRequestNodeDriverProxyHandle;
  chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle;
  chiRequestNodeMonitorProxy chiRequestNodeMonitorProxyHandle;
  uvm_analysis_port#(chiRequestNodeTx) chiRequestNodeAnalysisPort;
  uvm_sequencer#(chiRequestNodeTx) chiRequestNodeSequencerHandle;
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
  uvm_config_db#(chiRequestNodeAgentConfig) :: set(this,"chiRequestNodeDriverProxyHandle","chiRequestNodeDriverProxyHandle",chiRequestNodeAgentConfigHandle);
  uvm_config_db#(chiRequestNodeAgentConfig) :: set(this,"chiRequestNodeMonitorProxyHandle","chiRequestNodeMonitorProxyHandle",chiRequestNodeAgentConfigHandle);
  if(chiRequestNodeAgentConfigHandle.is_active ==UVM_ACTIVE)begin 
    chiRequestNodeDriverProxyHandle = chiRequestNodeDriverProxy :: type_id :: create("chiRequestNodeDriverProxyHandle",this);
    chiRequestNodeSequencerHandle = uvm_sequencer#(chiRequestNodeTx) :: type_id :: create("chiRequestNodeSequencerHandle",this);
  end 
    chiRequestNodeMonitorProxyHandle = chiRequestNodeMonitorProxy :: type_id :: create("chiRequestNodeMonitorProxyHandle",this);
    chiRequestNodeAnalysisPort = new($sformatf("chiRequestNodeAnalysisPort[%d]",requestNodeId),this);
endfunction 

function void chiRequestNodeAgent::connect_phase(uvm_phase phase);
  if(chiRequestNodeAgentConfigHandle.is_active ==UVM_ACTIVE)begin
    chiRequestNodeDriverProxyHandle.seq_item_port.connect(chiRequestNodeSequencerHandle.seq_item_export);
  end 
  chiRequestNodeMonitorProxyHandle.chiRequestNodeAnalysisPort.connect(this.chiRequestNodeAnalysisPort);
endfunction 

`endif 
