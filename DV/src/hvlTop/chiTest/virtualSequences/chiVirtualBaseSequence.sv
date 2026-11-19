`ifndef CHIVIRTUALBASESEQUENCE_INCLUDED
`define CHIVIRTUALBASESEQUENCE_INCLUDED

class chiVirtualBaseSequence extends uvm_sequence;
   `uvm_object_utils(chiVirtualBaseSequence)

   requestNodeBaseSequence requestNodeBaseSequenceHandle[int][];

   subordinateNodeBaseSequence subordinateNodeBaseSequenceHandle[];

   chiEnvConfig chiEnvConfigHandle;
   extern function new(string name="chiVirtualBaseSequence");

   extern virtual task body();

endclass

function chiVirtualBaseSequence :: new(string name="chiVirtualBaseSequence");
  super.new(name);
endfunction 

task chiVirtualBaseSequence::body();
  
  for(int i=0;i<chiEnvConfigHandle.numOfRequestNode;i++) begin
    if(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeTypeEnumHandle == RNF) begin 
      requestNodeBaseSequenceHandle[i] = new[chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].localProcessorCount];
    end 
    else begin 
      requestNodeBaseSequenceHandle[i] = new[1];
    end 
  end 
  
  subordinateNodeBaseSequenceHandle = new[chiEnvConfigHandle.numOfSubordinateNode];

  for(int i=0;i<(chiEnvConfigHandle.numOfRequestNode);i++) begin 
    if(chiEnvConfigHandle.chiRequestNodeAgentConfigHandle[i].requestNodeTypeEnumHandle == RNF) begin
      for(int j=0;j<$size(requestNodeBaseSequenceHandle[i],1);j++)begin 
         requestNodeBaseSequenceHandle[i][j] = requestNodeBaseSequence :: type_id :: create($sformatf("requestNodeBaseSequenceHandle[%d][%d]",i,j));
      end 
    end
    else begin 
     requestNodeBaseSequenceHandle[i][0] = requestNodeBaseSequence :: type_id :: create($sformatf("requestNodeBaseSequenceHandle[%d][%d]",i,0));
    end 
  end 

  fork
    begin 
      foreach(requestNodeBaseSequenceHandle[i,j]) begin
        fork 
          //start the request node sequence here 

        join_none 

      end 
      //have wait state for number of count to be equal to (num of reads
      //+ writes)
    end 

    begin 
      //start subordinate sequence here 
      //running forever 
    end 
 join
endtask 


`endif 
