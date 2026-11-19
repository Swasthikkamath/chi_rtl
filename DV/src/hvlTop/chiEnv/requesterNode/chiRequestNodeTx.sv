`ifndef CHIREQUESTNODETX_INCLUDED
`define CHIREQUESTNODETX_INCLUDED

class chiRequestNodeTx extends uvm_sequence_item;
  `uvm_object_utils(chiRequestNodeTx) 
 //define all the properties if needed use field macros for automation   
  extern function new(string name="chiRequestNodeTx");

endclass

function chiRequestNodeTx :: new(string name="chiRequestNodeTx");
  super.new(name);
endfunction 
`endif 
