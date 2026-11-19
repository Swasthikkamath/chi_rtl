`ifndef CHISUBORDINATENODEDRIVERBFM_INCLUDED
`define CHISUBORDINATENODEDRIVERBFM_INCLUDED

interface chiSubordinateNodeDriverBfm(chiInterface chiInterfaceHandle); // here define the ports in correct manner preferably use wire or logic data type //if there is going to be passive data type use wire (if there is no reset task which drives 'z
  timeunit 1ns;
  timeprecision 1ps;

  import chiGlobalsPkg::*;

  clocking chiSubordinateNodeCb@(posedge chiInterfaceHandle.clk);
    default input #1step output #1step;
  endclocking 

  task chiSubordinateNodeReqDriveLcrd(output int resourcePlane);
    //drive activating signals + wait for lcrd 
  endtask 

  task chiSubordinateNodeReqGetFlit(output  chiStruct chiStructHandle);
  
  endtask 

  task chiSubordinateNodeDataGetLcrd();

  endtask 

  task chiSubordinateNodeDataDriveFlit(input chiStruct chiStructHandle);

  endtask 

  task chiSubordinateNodeRespGetLcrd();

  endtask

  task chiSubordinateNodeRespDriveFlit(input chiStruct chiStructHandle);
  endtask 

  task chiSubordinateNodeDataDriveLcrd();
  endtask

  task chiSubordinateNodeDataGetFlit(output chiStruct chiStructHandle);
  endtask



endinterface 

`endif 
