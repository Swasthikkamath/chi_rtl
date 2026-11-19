`ifndef CHISUBORDINATENODEMONITORPROXY_INCLUDED
`define CHISUBORDINATENODEMONITORPROXY_INCLUDED 

class chiSubordinateNodeMonitorProxy extends uvm_monitor;
   `uvm_component_utils(chiSubordinateNodeMonitorProxy)
  
   uvm_analysis_port#(chiSubordinateNodeTx) chiSubordinateNodeAnalysisPort;

   extern function new(string name="chiSubordinateNodeMonitorProxy",uvm_component parent=null);
   extern virtual function void build_phase(uvm_phase phase);
   extern virtual task run_phase(uvm_phase phase);
endclass

function chiSubordinateNodeMonitorProxy::new(string name="chiSubordinateNodeMonitorProxy",uvm_component parent=null);
  super.new(name,parent);
endfunction


function void chiSubordinateNodeMonitorProxy::build_phase(uvm_phase phase);
  super.build_phase(phase);
  chiSubordinateNodeAnalysisPort = new("chiSubordinateNodeAnalysisPort",this);
endfunction 

task chiSubordinateNodeMonitorProxy::run_phase(uvm_phase phase);
  
endtask 


`endif 
