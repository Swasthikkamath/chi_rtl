`ifndef CHISUBORDINATENODEMONITORBFM_INCLUDED
`define CHISUBORDINATENODEMONITORBFM_INCLUDED

interface chiSubordinateNodeMonitorBfm(chiInterface chiInterfaceHandle); // here define the ports in correct manner preferably use wire or logic data type //if there is going to be passive data type use wire (if there is no reset task which drives 'z
  timeunit 1ns;
  timeprecision 1ps;
  import chiGlobalsPkg::*;

  clocking chiSubordinateNodeCb@(posedge chiInterfaceHandle.clk);
    default input #1step output #1step;
  endclocking 

  task chiSubordinateNodeReqDriveLcrd();
    //drive activating signals + wait for lcrd 
  endtask 

  task chiSubordinateNodeReqMonitorFlit(output chiStruct chiStructHandle);
  
  endtask 

  task chiSubordinateNodeDataGetLcrd();

  endtask 

  task chiSubordinateNodeDataMonitorFlit(output chiStruct chiStructHandle);

  endtask 

  task chiSubordinateNodeRespGetLcrd();

  endtask

  task chiSubordinateNodeRespMonitorFlit(output chiStruct chiStructHandle);
  endtask 

  task chiSubordinateNodeDataDriveLcrd();
  endtask


  task chiSubordinateNodeRxDataMonitorFlit(output chiStruct chiStructHandle);
  endtask

endinterface 

`endif 
