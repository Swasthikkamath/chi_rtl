`ifndef CHIREQUESTNODEDRIVERPROXY_INCLUDED
`define CHIREQUESTNODEDRIVERPROXY_INCLUDED 

class chiRequestNodeDriverProxy extends uvm_driver#(chiRequestNodeTx);
  `uvm_component_utils(chiRequestNodeDriverProxy)

  virtual chiRequestNodeDriverBfm chiRequestNodeDriverBfmHandle;

  static longint tgtIdQueue[homeNodeTypeEnum][][$];
  longint typeBasedAddressPartition[homeNodeTypeEnum][$];
  int numOfAddress[homeNodeTypeEnum];
  int numOfAddressPerType[homeNodeTypeEnum][numOfHnf];
  chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle;
  chiRequestNodeLocalProcessor chiRequestNodeLocalProcessorHandle[]; 
  extern function new(string name="chiRequestNodeDriverProxy",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
  extern virtual function int  applyRnSam(longint physicalAddress);
  extern virtual function void addressPartition();
  extern virtual function void setUpTgtIdQueue();
endclass

function void chiRequestNodeDriverProxy :: addressPartition();
  foreach(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i]) begin 
    if(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i].homeNodeTypeEnumHandle == HNF) begin 
      typeBasedAddressPartition[HNF].push_back(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i].physicalAddress);
      numOfAddress[HNF]++;
    end 
    else if(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i].homeNodeTypeEnumHandle == HNI) begin 
      typeBasedAddressPartition[HNI].push_back(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i].physicalAddress);
      numOfAddress[HNI]++;
    end 
    else begin
      typeBasedAddressPartition[MN].push_back(chiRequestNodeAgentConfigHandle.chiRequestNodeSamConfigHandle[i].physicalAddress);
      numOfAddress[MN]++;
    end 
  end 
  foreach(numOfAddressPerType[i]) begin 
    if(i == HNF) begin 
      for(int j=0;j<numOfHnf;j++)
        numOfAddressPerType[i][j] = (numOfAddress[HNF]/numOfHnf);
      if(numOfAddress[i] % numOfHnf !=0) begin 
        numOfAddressPerType[i][numOfHnf-1] = numOfAddressPerType[i][numOfHnf-1]+numOfAddress[i] % numOfHnf;
      end 
    end 
    else if(i==HNI) begin 
      for(int j=0;j<numOfHni;j++)
        numOfAddressPerType[i][j] = (numOfAddress[HNI]/numOfHni);
      if(numOfAddress[i] % numOfHni !=0) begin 
        numOfAddressPerType[i][numOfHni-1] = numOfAddressPerType[i][numOfHni-1]+numOfAddress[i] % numOfHni;
      end 
    end 
    else begin 
      for(int j=0;j<numOfMn;j++)
        numOfAddressPerType[i][j] = (numOfAddress[MN]/numOfMn);
      if(numOfAddress[i] % numOfMn !=0) begin 
        numOfAddressPerType[i][numOfMn-1] = numOfAddressPerType[i][numOfMn-1]+numOfAddress[i] % numOfMn;
      end 
    end 
  end 
endfunction 
function void chiRequestNodeDriverProxy :: setUpTgtIdQueue();
  addressPartition();
  foreach(tgtIdQueue[i]) begin
    if(i == HNF) begin 
      for(int j=0;j<numOfHnf ;j++) begin 
        for(int k =0 ;k < numOfAddressPerType[i][j];k++) begin
           tgtIdQueue[i][j].push_back(typeBasedAddressPartition[i].pop_front());
        end 
      end 
    end 
    else if(i==HNI)begin 
     for(int j=0;j<numOfHni ;j++) begin 
        for(int k =0 ;k < numOfAddressPerType[i][j];k++) begin
           tgtIdQueue[i][j].push_back(typeBasedAddressPartition[i].pop_front());
        end 
      end 
    end 
    else begin 
      for(int j=0;j<numOfMn ;j++) begin 
        for(int k =0 ;k < numOfAddressPerType[i][j];k++) begin
           tgtIdQueue[i][j].push_back(typeBasedAddressPartition[i].pop_front());
        end 
      end   
    end 
  end 
endfunction 

function int chiRequestNodeDriverProxy :: applyRnSam(longint physicalAddress);
  setUpTgtIdQueue();
  foreach(tgtIdQueue[i,j])begin 
    for(int k=0;k<(tgtIdQueue[i][j].size());k++)begin 
       if(tgtIdQueue[i][j][k] == physicalAddress)begin 
         return chiRequestNodeAgentConfigHandle.hnfNodeIdConfig[i][j]; 
       end 
    end 
  end 
endfunction 
function chiRequestNodeDriverProxy :: new(string name="chiRequestNodeDriverProxy",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiRequestNodeDriverProxy::build_phase(uvm_phase phase);
//get the config here 
  if(!(uvm_config_db #(chiRequestNodeAgentConfig)::get(this,"","chiRequestNodeAgentConfig",chiRequestNodeAgentConfigHandle)))begin 
    `uvm_fatal("DRIVER PROXY","FAILED TO GET CONFIG")
  end 

  chiRequestNodeLocalProcessorHandle = new[chiRequestNodeAgentConfigHandle.localProcessorCount];
  foreach(chiRequestNodeLocalProcessorHandle[i])begin 
    chiRequestNodeLocalProcessorHandle[i] = chiRequestNodeLocalProcessor :: type_id :: create($sformatf("chiRequestNodeLocalProcessorHandle[%d]",i));
    chiRequestNodeLocalProcessorHandle[i].createCache(chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[i],0);
  end 
  chiRequestNodeDriverBfmHandle = chiRequestNodeAgentConfigHandle.chiRequestNodeDriverBfmHandle;

  foreach(tgtIdQueue[i])begin 
    if(i == HNF) begin 
      tgtIdQueue[HNF] = new[numOfHnf];
    end 
    else if(i == HNI) begin 
      tgtIdQueue[HNI] = new[numOfHni];
    end 
    else if(i == MN) begin 
      tgtIdQueue[MN] = new[numOfMn];
    end 
  end 
endfunction 

task chiRequestNodeDriverProxy::run_phase(uvm_phase phase);
 //implement the relationships between channel threads here and calling of the
 //task here 
  //
  //need a infinite thread which waits for reset to run booting of all local processors also when reset happens the upper threads should be killed and also its subprocessess too but after reset it should restart again
  process chiLinkTransferProcess;
  forever begin //should check whether forever inside forever will create issue last time it has create prob simulate it and check if not find other solution 
    fork 
      begin 
        chiLinkTransferProcess = process::self;
        forever begin 
          bit tlbHitOrMiss;
          bit gptHitOrMiss;
          bit dataHitOrMiss;
          bit pasMatch;
          longint physicalAddress;
          bit writeThrough;
          bit evict;
          bit[MAXGRANULESIZE-1:0] data;
          bit[ADDRESSWIDTH-1:0]evictAddress;
          bit allocate;
          //get the sequence item here 
          chiRequestNodeTx chiRequestNodeTxHandle; //need automatic handle or else same handle will be used for each outstanding thread if req handle will be used directly so to prevent that declaring automatic handle
          seq_item_port.get_next_item(chiRequestNodeTxHandle);
          physicalAddress = chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].translateVirtualAddress(chiRequestNodeTxHandle,chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],tlbHitOrMiss);
          if(tlbHitOrMiss ==0) begin 
            //through bfm start 4 level or 3 level tlb table walker 
          end 
          else begin 
            //chiRequestNodeTxHandle.PAS = (chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].currentEl == EL3) ? (root ) : (()  ) //use ns from tlb + scrEL3 regg to decide the pas look at comnbo
            chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].checkForSecurityWorld(physicalAddress,chiRequestNodeTxHandle,chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],gptHitOrMiss,pasMatch);
            if(gptHitOrMiss == 0) begin 
              //call bfm task for gpt table walker 
            end 
          end
          if(chiRequestNodeTxHandle.writeOrRead==1)begin 
            chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].writeToBlock(physicalAddress,chiRequestNodeTxHandle.data,chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],writeThrough,data,evict,evictAddress,allocate);

            if(|({evict,writeThrough})!=1)begin 
              continue;  
            end 
          end 
          else begin 
            dataHitOrMiss = chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].checkForBlock(physicalAddress,chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],chiRequestNodeTxHandle);
            if(dataHitOrMiss==1) begin 
              continue;
            end 
          end 
          
          applyRnSam(physicalAddress);         
          // 
          fork
            //initiate the channels here 
          join_any 
        end 
      end 

      begin 
         //reset wait 
        chiRequestNodeDriverBfmHandle.chiRequesterNodeWaitForReset();
        chiLinkTransferProcess.kill();
        for(int i=0;i<chiRequestNodeAgentConfigHandle.localProcessorCount;i++) begin 
          chiRequestNodeLocalProcessorHandle[i].applyBootSetting(chiRequestNodeAgentConfigHandle.requestNodeLocalProcessorConfigHandle[i]);
        end        
      end 
    join
  end 
endtask 


`endif 
