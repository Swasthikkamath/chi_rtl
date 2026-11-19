`ifndef CHIREQUESTNODEDRIVERPROXY_INCLUDED
`define CHIREQUESTNODEDRIVERPROXY_INCLUDED 

class chiRequestNodeDriverProxy extends uvm_driver#(chiRequestNodeTx);
  `uvm_component_utils(chiRequestNodeDriverProxy)

  extern function new(string name="chiRequestNodeDriverProxy",uvm_component parent=null);
  extern virtual function void build_phase(uvm_phase phase);
  extern virtual task run_phase(uvm_phase phase);
endclass

function chiRequestNodeDriverProxy :: new(string name="chiRequestNodeDriverProxy",uvm_component parent=null);
  super.new(name,parent);
endfunction 

function void chiRequestNodeDriverProxy::build_phase(uvm_phase phase);
//get the config here 
endfunction 

task chiRequestNodeDriverProxy::run_phase(uvm_phase phase);
 //implement the relationships between channel threads here and calling of the
 //task here 
endtask 


`endif 
