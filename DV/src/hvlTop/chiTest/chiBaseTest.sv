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
  
    if(!(uvm_config_db#(virtual chiRequestNodeDriverBfm) :: get(this,"",$sformatf("chiRequestNodeDriverBfmHandle[%d]",i),chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].chiRequestNodeDriverBfmHandle)))begin 
      `uvm_fatal("uvm_test_top","failed to get driver bfm")
    end 
   
    if(!(uvm_config_db#(virtual chiRequestNodeMonitorBfm) :: get(this,"",$sformatf("chiRequestNodeMonitorBfmHandle[%d]",i),chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].chiRequestNodeMonitorBfmHandle)))begin 
      `uvm_fatal("uvm_test_top","failed to get Monitor bfm")
    end 
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].is_active = uvm_active_passive_enum'(UVM_ACTIVE);
  
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle = new[chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].localProcessorCount];

    foreach(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j]) begin
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j] = requestNodeLocalProcessorConfig :: type_id :: create($sformatf("chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[%d].chiRequestNodeLocalProcessorConfigHandle[%d]",i,j));  
      
      std::randomize(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].securityLevelHandle)with{chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].securityLevelHandle inside {[0:4]}};

      //upate the base address for tlb based on asid 
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].gptCacheGranuleSize = 6; //64 byte (2^6)
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].gptNumOfWays=4;
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].gptCacheSize = FOUREKILOBYTES;

      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].tlbCacheGranuleSize = 3;
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].tlbNumOfWays=4;
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].tlbCacheSize = FOUREKILOBYTES;

      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].dataCacheGranuleSize = 6;
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].dataNumOfWays=4;
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].gptCacheSize = FOUREKILOBYTES;
    end 
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
  //update the tlb base address based on asid 
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].mainMemory = 1;
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].numOfTlbInfo = 2;
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].addressRangeTlbInfoStructHandle = new[chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].numOfTlbInfo]; //now user can specify the shareability(which address rannge is snoopable and which is not using this config property )
 //below is basic level address map done if needed user can override this config before sequence is called or override in build phase 
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
