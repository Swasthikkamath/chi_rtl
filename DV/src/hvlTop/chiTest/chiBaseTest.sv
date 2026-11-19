`ifndef CHIBASETEST_INCLUDED
`define CHIBASETEST_INCLUDED


class chiBaseTest extends uvm_test;
  `uvm_component_utils(chiBaseTest)
  chiEnv chiEnvHandle;
  chiEnvConfig chiEnvConfigHandle;

  extern function new(string name="chiBaseTest",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void end_of_elaboration_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void setUpEnvConfig();
  extern virtual function void setUpRequestNodeConfig();
  extern virtual function void setUpSubordinateNodeConfig();
  extern virtual function void setUpRequestNodeLocalProcessorConfig(int numOfLocalProcessor,int requestNodeId);
endclass
function chiBaseTest::new(string name="chiBaseTest",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiBaseTest::setUpRequestNodeLocalProcessorConfig(int numOfLocalProcessor,int requestNodeId);
  chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requestNodeId].requestNodeLocalProcessorConfigHandle = new[numOfLocalProcessor];
  foreach(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requestNodeId].requestNodeLocalProcessorConfigHandle[i]) begin 
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requestNodeId].requestNodeLocalProcessorConfigHandle[i] = requestNodeLocalProcessorConfig :: type_id :: create($sformatf("requestNodeLocalProcessorConfig[%d]",i));
  end 
endfunction 

function void chiBaseTest::setUpRequestNodeConfig();
  chiEnvConfigHandle.chiRequestNodeAgentConfigHandle = new[chiEnvConfigHandle.numOfRequestNode];
  foreach(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i]) begin 
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i] = chiRequestNodeAgentConfig :: type_id :: create($sformatf("chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[%d]",i));
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].is_active = uvm_active_passive_enum'(UVM_ACTIVE);
  end 
 // here test engineer can set the required type and local processor count for
 // each agent config 
 // and then set call setUpRequestNodeLocalProcessorConfig to create config
 // for each request node and then set config for each 
endfunction

function void chiBaseTest::setUpSubordinateNodeConfig();
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle = new[chiEnvConfigHandle.numOfSubordinateNode];
  foreach(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i]) begin
    chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i] = chiSubordinateNodeAgentConfig :: type_id :: create($sformatf("chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[%d]",i));
    chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i].is_active = uvm_active_passive_enum'(UVM_ACTIVE);
  end
 // here test engineer can set the required type and local processor count for
 // each agent config
endfunction

function void chiBaseTest::setUpEnvConfig();
  chiEnvConfigHandle = chiEnvConfig :: type_id :: create("chiEnvConfigHandle");
  chiEnvConfigHandle.numOfRequestNode = NUMOFREQUESTNODE;
  chiEnvConfigHandle.numOfSubordinateNode = NUMOFSUBORDINATENODE; 
  setUpRequestNodeConfig();
  setUpSubordinateNodeConfig();
endfunction 

function void chiBaseTest::build_phase(uvm_phase phase);
  super.build_phase(phase);
  setUpEnvConfig();
  uvm_config_db#(chiEnvConfig) :: set(this,"chiEnvHandle","chiEnvConfigHandle",chiEnvConfigHandle);
  chiEnvHandle = chiEnv :: type_id :: create("chiEnvHandle",this);
endfunction 

function void chiBaseTest::end_of_elaboration_phase(uvm_phase phase);
  uvm_root::get().print_topology();
endfunction 

task chiBaseTest::run_phase(uvm_phase phase);
  super.run_phase(phase);
  phase.raise_objection(this,"raised objection from the test");
  phase.drop_objection(this,"drop objection from the test");
endtask 


`endif 
