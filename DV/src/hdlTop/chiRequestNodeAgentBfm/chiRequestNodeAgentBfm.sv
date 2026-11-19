`ifndef CHIREQUESTNODEAGENTBFM_INCLUDED
`define CHIREQUESTNODEAGENTBFM_INCLUDED

interface chiRequestNodeAgentBfm#(parameter int nodeId=0)(chiInterface chiInterfaceHandle);
  timeunit 1ns;
  timeprecision 1ps;
  `include"uvm_macros.svh"
  import uvm_pkg::*;
  chiRequestNodeDriverBfm chiRequestNodeDriverBfmHandle(chiInterfaceHandle.chiRequestNodeDriverModport);
  chiRequestNodeMonitorBfm chiRequestNodeMonitorBfmHandle(chiInterfaceHandle.chiRequestNodeMonitorModport);

  initial begin 
    uvm_config_db#(virtual chiRequestNodeDriverBfm) :: set(null,"uvm_test_top",$sformatf("chiRequestNodeDriverBfmHandle[%d]",nodeId),chiRequestNodeDriverBfmHandle);
    uvm_config_db #(virtual chiRequestNodeMonitorBfm) :: set(null,"uvm_test_top",$sformatf("chiRequestNodeMonitorBfmHandle[%d]",nodeId),chiRequestNodeMonitorBfmHandle);
  end 
endinterface 
`endif 
  
