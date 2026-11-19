`ifndef CHISUBORDINATENODEAGENT_INCLUDED 
`define CHISUBORDINATENODEAGENT_INCLUDED

class chiSubordinateNodeAgent extends uvm_agent;
  `uvm_component_utils(chiSubordinateNodeAgent) //may be we can think of automation of certain object or config property
  int subordinateNodeId;
  chiSubordinateNodeDriverProxy chiSubordinateNodeDriverProxyHandle;
  chiSubordinateNodeMonitorProxy chiSubordinateNodeMonitorProxyHandle;
  uvm_sequencer#(chiSubordinateNodeTx) chiSubordinateNodeSequencerHandle;
  chiSubordinateNodeAgentConfig chiSubordinateNodeAgentConfigHandle;
  uvm_analysis_port#(chiSubordinateNodeTx) chiSubordinateNodeAnalysisPort;
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
  uvm_config_db#(chiSubordinateNodeAgentConfig) :: set(this,"chiSubordinateNodeDriverProxyHandle","chiSubordinateNodeDriverProxyHandle",chiSubordinateNodeAgentConfigHandle);
  uvm_config_db#(chiSubordinateNodeAgentConfig) :: set(this,"chiSubordinateNodeMonitorProxyHandle","chiSubordinateNodeMonitorProxyHandle",chiSubordinateNodeAgentConfigHandle);
  if(chiSubordinateNodeAgentConfigHandle.is_active==UVM_ACTIVE) begin 
    chiSubordinateNodeDriverProxyHandle = chiSubordinateNodeDriverProxy :: type_id :: create("chiSubordinateNodeDriverProxyHandle",this);
    chiSubordinateNodeSequencerHandle = uvm_sequencer#(chiSubordinateNodeTx) :: type_id :: create("chiSubordinateNodeSequencerHandle",this);
  end 
  chiSubordinateNodeMonitorProxyHandle = chiSubordinateNodeMonitorProxy :: type_id :: create("chiSubordinateNodeMonitorProxyHandle",this);
  chiSubordinateNodeAnalysisPort = new($sformatf("chiSubordinateNodeAnalysisPort[%d]",subordinateNodeId),this);
endfunction 

function void chiSubordinateNodeAgent::connect_phase(uvm_phase phase);
  if(chiSubordinateNodeAgentConfigHandle.is_active==UVM_ACTIVE) begin
    chiSubordinateNodeDriverProxyHandle.seq_item_port.connect(chiSubordinateNodeSequencerHandle.seq_item_export);
  end 
  chiSubordinateNodeMonitorProxyHandle.chiSubordinateNodeAnalysisPort.connect(this.chiSubordinateNodeAnalysisPort);
endfunction 

`endif 
