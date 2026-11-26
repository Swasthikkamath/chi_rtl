`ifndef CHIREQUESTNODEDRIVERPROXY_INCLUDED
`define CHIREQUESTNODEDRIVERPROXY_INCLUDED 

class chiRequestNodeDriverProxy extends uvm_driver#(chiRequestNodeTx);
  `uvm_component_utils(chiRequestNodeDriverProxy)

  virtual chiRequestNodeDriverBfm chiRequestNodeDriverBfmHandle;

  chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle;
  chiRequestNodeLocalProcessor chiRequestNodeLocalProcessorHandle[]; 
  extern function new(string name="chiRequestNodeDriverProxy",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
endclass

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
    chiRequestNodeLocalProcessorHandle[i].createCache(chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[i]);
  end 
  chiRequestNodeDriverBfmHandle = chiRequestNodeAgentConfigHandle.chiRequestNodeDriverBfmHandle;
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
          bit[MAXGRANULESIZE-1:0 data];
          bit[ADDRESSWIDTH-1:0]evictAddress;
          bit allocate;
          //get the sequence item here 
          chiRequestNodeTx chiRequestNodeTxHandle; //need automatic handle or else same handle will be used for each outstanding thread if req handle will be used directly so to prevent that declaring automatic handle
          seq_item_port.get_next_item(chiRequestNodeTxHandle);
          physicalAddress = chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].translateVirtualAddress(chiRequestNodeTxHandle,chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],tlbHitOrMiss)
          if(tlbHitOrMiss ==0) begin 
            //through bfm start 4 level or 3 level tlb table walker 
          end 
          else begin 
            chiRequestNodeTxHandle.PAS = (chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].currentEl == EL3) ? (root ) : (()  ) //use ns from tlb + scrEL3 reg to decide the pas look at comnbo
            chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].checkForSecurityWorld(physicalAddress,chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],gptHitOrMiss,pasMatch);
            if(gptHitOrMiss == 0) begin 
              //call bfm task for gpt table walker 
            end 
          end
          if(chiRequestNodeTxHandle.writeOrRead==1)begin 
            chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].writeToBlock(physicalAddress,chiRequestNodeTxHandle,chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID],writeThrough,data,evict,evictAddress,allocate);

            if(|({evict,writeThrough})!=1)begin 
              continue;  
            end 
          end 
          else begin 
            dataHitOrMiss = chiRequestNodeLocalProcessorHandle[chiRequestNodeTxHandle.LPID].checkForBlock(physicalAddress,chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[chiRequestNodeTxHandle.LPID]);
            if(dataHitOrMiss==1) begin 
              continue;
            end 
          end 
          
          
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
          chiRequestNodeLocalProcessorHandle[i].applyBootSetting(chiRequestNodeAgentConfigHandle.chiRequestNodeLocalProcessorConfigHandle[i]);
        end        
      end 
  join 
endtask 


`endif 
