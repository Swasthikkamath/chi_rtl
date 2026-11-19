`ifndef CHISUBORDINATENODEDRIVERPROXY_INCLUDED
`define CHISUBORDINATENODEDRIVERPROXY_INCLUDED 

class chiSubordinateNodeDriverProxy extends uvm_driver#(chiSubordinateNodeTx);
  `uvm_component_utils(chiSubordinateNodeDriverProxy)

  extern function new(string name="chiSubordinateNodeDriverProxy",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
endclass

function chiSubordinateNodeDriverProxy :: new(string name="chiSubordinateNodeDriverProxy",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiSubordinateNodeDriverProxy::build_phase(uvm_phase phase);
//get the config here 
endfunction 

task chiSubordinateNodeDriverProxy::run_phase(uvm_phase phase);
 //implement the relationships between channel threads here and calling of the
 //task here 
endtask 


`endif 
