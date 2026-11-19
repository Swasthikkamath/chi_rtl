`ifndef CHISUBORDINATENODETX_INCLUDED
`define CHISUBORDINATENODETX_INCLUDED

class chiSubordinateNodeTx extends uvm_sequence_item;
  `uvm_object_utils(chiSubordinateNodeTx) 
 //define all the properties if needed use field macros for automation   
  extern function new(string name="chiSubordinateNodeTx");

endclass

function chiSubordinateNodeTx :: new(string name="chiSubordinateNodeTx");
  super.new(name);
endfunction 
`endif 
