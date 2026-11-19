`ifndef REQUESTNODEBASESEQUENCE_INCLUDED
`define REQUESTNODEBASESEQUENCE_INCLUDED

class requestNodeBaseSequence extends uvm_sequence#(chiRequestNodeTx);
  `uvm_object_utils(requestNodeBaseSequence)
  static int requestNodeCompletionCount;
  int localProcessorId;
  requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle;  
  extern function new(string name="requestNodeBaseSequence");

  extern virtual task body();
endclass
function requestNodeBaseSequence :: new(string name="requestNodeBaseSequence");
  super.new(name);
endfunction 

task requestNodeBaseSequence :: body();
  if(!(uvm_config_db #(requestNodeLocalProcessorConfig) :: get(null,get_full_name(),$sformatf("requestNodeLocalProcessorConfigHandle[%d]",localProcessorId),requestNodeLocalProcessorConfigHandle))) begin 
    `uvm_fatal("REQUEST NODE BASE SEQUENCE",$sformatf("FAILED TO GET CONFIG FOR LOCAL PROCESSOR %D",localProcessorId))
  end 
  for(int i=0 ; i<requestNodeLocalProcessorConfigHandle.numOfReads ;i++) begin
    automatic int id; 
    req = chiRequestNodeTx :: type_id :: create({get_name(),".","request"});
    start_item(req);
//    req.randomize();
    finish_item(req);
    id = req.get_transaction_id();
    fork  
      begin
        RSP rsp;
	get_response(rsp,id);
	requestNodeCompletionCount++;
      end 
    join_none 
  end 
  for(int i=0 ; i<requestNodeLocalProcessorConfigHandle.numOfWrites ;i++) begin
    automatic int id;
    req = chiRequestNodeTx :: type_id :: create({get_name(),".","request"});
    start_item(req);
   // req.randomize();
    finish_item(req);
    id = req.get_transaction_id();
    fork
      begin
        RSP rsp;
        get_response(rsp,id);
        requestNodeCompletionCount++;
      end
    join_none
  end

endtask 

`endif 



