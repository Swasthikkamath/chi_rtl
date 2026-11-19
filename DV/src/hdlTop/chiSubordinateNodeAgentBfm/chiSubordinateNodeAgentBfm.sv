`ifndef CHISUBORDINATENODEAGENTBFM_INCLUDED
`define CHISUBORDINATENODEAGENTBFM_INCLUDED

interface chiSubordinateNodeAgentBfm#(parameter int nodeId=0)(chiInterface chiInterfaceHandle);
  timeunit 1ns;
  timeprecision 1ps;
  `include"uvm_macros.svh"
  import uvm_pkg::*;
  chiSubordinateNodeDriverBfm chiSubordinateNodeDriverBfmHandle(chiInterfaceHandle.chiSubordinateNodeDriverModport);
  chiSubordinateNodeMonitorBfm chiSubordinateNodeMonitorBfmHandle(chiInterfaceHandle.chiSubordinateNodeMonitorModport);

  initial begin 
    uvm_config_db #(virtual chiSubordinateNodeDriverBfm) :: set(null,"uvm_test_top",$sformatf("chiSubordinateNodeDriverBfmHandle[%d]",nodeId),chiSubordinateNodeDriverBfmHandle);
    uvm_config_db #(virtual chiSubordinateNodeMonitorBfm) :: set(null,"uvm_test_top",$sformatf("chiSubordinateNodeMonitorBfmHandle[%d]",nodeId),chiSubordinateNodeMonitorBfmHandle);
  end 
endinterface 
`endif 
  
