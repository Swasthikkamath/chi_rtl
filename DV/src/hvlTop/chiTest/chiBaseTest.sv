`ifndef CHIBASETEST_INCLUDED
`define CHIBASETEST_INCLUDED


class chiBaseTest extends uvm_test;
  `uvm_component_utils(chiBaseTest)
  chiEnv chiEnvHandle;
  chiEnvConfig chiEnvConfigHandle;
  longint levelIntermidiateAddress[][longint];
  longint pageStartingAddress[$];
  int arrRnNodeIdQueue[$] = '{'h280,'h 301,'h 482, 'h143, 'h244};
  extern function new(string name="chiBaseTest",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual function void end_of_elaboration_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function void setUpEnvConfig();
  extern virtual function void setUpRequestNodeConfig();
  extern virtual function void setUpSubordinateNodeConfig();
  extern virtual function void setUpRequestNodeLocalProcessorConfig(int numOfLocalProcessor,int requestNodeId);
  extern virtual function void setUpStartingAddress();
  extern virtual function void setUpAsidBaseAddress();
  extern virtual function void setUpWalkerAddress();
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
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].rnNodeId = arrRnNodeIdQueue.pop_front();
  
    chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle = new[chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].localProcessorCount];

    foreach(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j]) begin
      chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j] = requestNodeLocalProcessorConfig :: type_id :: create($sformatf("chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[%d].chiRequestNodeLocalProcessorConfigHandle[%d]",i,j));  
      
      std::randomize(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].securityLevelHandle)with{chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeLocalProcessorConfigHandle[j].securityLevelHandle inside {[0:4]};};

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

function void chiBaseTest :: setUpStartingAddress();
  for(int i=ioAddressMapStartingAddress ; i<=ioAddressMapEndingAddress; i += (pageSize *1024) )begin 
    if(i % (pageSize*1024) !=0) begin
      automatic int quotient;
      quotient = i /(pageSize*1024);
      i = (quotient +1) *(pageSize * 1024);
    end 
    pageStartingAddress.push_back(i);
  end 
endfunction 

function void chiBaseTest :: setUpAsidBaseAddress();
  for(int subordinate=0;subordinate < chiEnvConfigHandle.numOfSubordinateNode ; subordinate++)begin
    if(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].mainMemory ==1) begin 
      for(int process=0;process<numOfProcess ;process++) begin 
        std::randomize(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].programBasedBaseAddress[process]) with{chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].programBasedBaseAddress[process] inside{pageStartingAddress};};
        for(int i=0 ; i < pageStartingAddress.size() ;i++) begin 
          if(pageStartingAddress[i] == chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].programBasedBaseAddress[process])begin 
            pageStartingAddress.delete(i);
            break;
          end 
        end 
      end 
    end 
  end 
endfunction 

function void chiBaseTest:: setUpWalkerAddress();
  foreach(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate]) begin 
    if(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].mainMemory == 1) begin
      for(int process=0; process<numOfProcess ; process++) begin 
        foreach(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].addressRangeTlbInfoStructHandle[tlbInfo]) begin 
          for(int address=chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].addressRangeTlbInfoStructHandle[tlbInfo].startAddress ; address <= chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].addressRangeTlbInfoStructHandle[tlbInfo].endAddress ; address += 8)begin 
            static int count;
            automatic longint partSelectIndex;
            automatic longint levelIndex;
            automatic int quotient;

            count++;
             if(address % 8 != 0) begin 
               quotient = address/8;
               address = (quotient +1) * 8;
             end 

            for(int levels =0 ; levels<level ; levels++) begin 
              automatic longint localAddress;
              automatic int usedBits;
              automatic byte mairbyte;
              automatic bit[($clog2(( pageSize* 1024  )/8))-1:0] partSelect;
              usedBits = ($clog2(pageSize * 1024)) + (level * ($clog2(( pageSize* 1024)/8)));
              if(levels ==0) begin 
                if(usedBits == ADDRESSWIDTH) begin 
                  partSelectIndex= ADDRESSWIDTH -1;
                end 
                else begin 
                  partSelectIndex = ADDRESSWIDTH - (ADDRESSWIDTH -usedBits)-1; //44;
                end 
              end 
              for(int i=partSelectIndex,j=$high(partSelect) ;i>(partSelectIndex -($clog2(( pageSize* 1024 )/8))) ;i--,j--) begin 
                partSelect[j] = address[i];
              end 

              if(levels ==0) begin 
                levelIndex = chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].programBasedBaseAddress[process];
                levelIndex = levelIndex + ((partSelect-1)* 8);  // 3040 
              end 
              else begin 
                levelIndex = levelIntermidiateAddress[levels-1][levelIndex];  
                levelIndex = levelIndex + ((partSelect-1)* 8);  
              end 
              if(levelIntermidiateAddress[levels].exists(levelIndex)) begin  //0 1 ( level 1, level2 , level 3 , level 4 )
                localAddress = levelIntermidiateAddress[levels][levelIndex];
              end 
              else begin 
                std::randomize(localAddress) with{localAddress inside{pageStartingAddress};}; //7000
                for(int i=0 ;i < pageStartingAddress.size();i++) begin 
                  if(pageStartingAddress[i] == localAddress)begin 
                    pageStartingAddress.delete(i);
                    break;
                  end
                end
                levelIntermidiateAddress[levels][levelIndex] = localAddress; 
              end 
              chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].addressRangeTlbInfoStructHandle[tlbInfo].walkerLevelAddress[address][levels].push_back(localAddress);
              for(int requester=0;requester<chiEnvConfigHandle.numOfRequestNode ; requester++) begin 
                automatic int startingIndex;
                chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requester].chiRequestNodeSamConfigHandle = new[count](chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requester].chiRequestNodeSamConfigHandle);
                chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requester].chiRequestNodeSamConfigHandle[count-1].physicalAddress = localAddress;
                startingIndex = (chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[subordinate].addressRangeTlbInfoStructHandle[tlbInfo].tlbConfigStructHandle.ATTRINDX) * 8;
                mairbyte = MAIR[startingIndex +: 8];
                if(mairbyte[7:4] == 0)begin 
                  chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requester].chiRequestNodeSamConfigHandle[count-1].homeNodeTypeEnumHandle = HNI;
                end 
                else begin 
                  chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[requester].chiRequestNodeSamConfigHandle[count-1].homeNodeTypeEnumHandle = HNF;
                end 
              end 
            end 
          end 
        end 
      end 
    end 
  end 
endfunction

function void chiBaseTest::setUpSubordinateNodeConfig();
  setUpStartingAddress();
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle = new[chiEnvConfigHandle.numOfSubordinateNode];
  foreach(chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i]) begin
    chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i] = chiSubordinateNodeAgentConfig :: type_id :: create($sformatf("chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[%d]",i));
    chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[i].is_active = uvm_active_passive_enum'(UVM_ACTIVE);
  end
  //update the tlb base address based on asid 
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].mainMemory = 1;
  setUpAsidBaseAddress();
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].numOfTlbInfo = 2;
  chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].addressRangeTlbInfoStructHandle = new[chiEnvConfigHandle.chiSubordinateNodeAgentConfigHandle[0].numOfTlbInfo]; //now user can specify the shareability(which address rannge is snoopable and which is not using this config property )
 //below is basic level address map done if needed user can override this config before sequence is called or override in build phase 
 // each agent config
   
endfunction

function void chiBaseTest::setUpEnvConfig();
  chiEnvConfigHandle = chiEnvConfig :: type_id :: create("chiEnvConfigHandle");
  chiEnvConfigHandle.numOfRequestNode = NUMOFREQUESTNODE;
  chiEnvConfigHandle.numOfSubordinateNode = NUMOFSUBORDINATENODE; 
  setUpSubordinateNodeConfig();
  setUpRequestNodeConfig();
  setUpWalkerAddress();
endfunction 

function void chiBaseTest::build_phase(uvm_phase phase);
  super.build_phase(phase);
  levelIntermidiateAddress = new[level];
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
