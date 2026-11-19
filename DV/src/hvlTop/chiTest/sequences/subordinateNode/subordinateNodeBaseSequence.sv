`ifndef SUBORDINATENODEBASESEQUENCE_INCLUDED
`define SUBORDINATENODEBASESEQUENCE_INCLUDED

class subordinateNodeBaseSequence extends uvm_sequence#(chiSubordinateNodeTx);
  `uvm_object_utils(subordinateNodeBaseSequence)
  static int subordinateNodeCompletionCount;
  int localProcessorId;
  extern function new(string name="subordinateNodeBaseSequence");

  extern virtual task body();
endclass
function subordinateNodeBaseSequence :: new(string name="subordinateNodeBaseSequence");
  super.new(name);
endfunction 

task subordinateNodeBaseSequence :: body();
    req = chiSubordinateNodeTx :: type_id :: create({get_name(),".","subordinate"});
    start_item(req);
//    req.randomize();
    finish_item(req);
//this will be running forever 
endtask 

`endif 



