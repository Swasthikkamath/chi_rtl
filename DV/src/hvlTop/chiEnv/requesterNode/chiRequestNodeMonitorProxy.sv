`ifndef CHIREQUESTNODEMONITORPROXY_INCLUDED
`define CHIREQUESTNODEMONITORPROXY_INCLUDED 

class chiRequestNodeMonitorProxy extends uvm_monitor;
   `uvm_component_utils(chiRequestNodeMonitorProxy)
  
   extern function new(string name="chiRequestNodeMonitorProxy",uvm_component parent=null);
   extern virtual function void build_phase(uvm_phase phase);
   extern virtual task run_phase(uvm_phase phase);
endclass

function chiRequestNodeMonitorProxy::new(string name="chiRequestNodeMonitorProxy",uvm_component parent=null);
  super.new(name,parent);
endfunction


function void chiRequestNodeMonitorProxy::build_phase(uvm_phase phase);
  super.build_phase(phase);
endfunction 

task chiRequestNodeMonitorProxy::run_phase(uvm_phase phase);
  
endtask 


`endif 
