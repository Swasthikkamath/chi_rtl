`ifndef CHIREQUESTNODEDRIVERBFM_INCLUDED
`define CHIREQUESTNODEDRIVERBFM_INCLUDED

interface chiRequestNodeDriverBfm(chiInterface chiInterfaceHandle); // here define the ports in correct manner preferably use wire or logic data type //if there is going to be passive data type use wire (if there is no reset task which drives 'z
  timeunit 1ns;
  timeprecision 1ps;
import chiGlobalsPkg::*;

clocking chiRequestNodeCb@(posedge chiInterfaceHandle.clk);
  default input #1step output #1step;
endclocking 

task chiRequestNodeReqGetLcrd(output int resourcePlane);
  //drive activating signals + wait for lcrd 
endtask 

task chiRequestNodeReqDriveFlit(input chiStruct chiStructHandle);
  
endtask 

task chiRequestNodeDataGetLcrd();

endtask 

task chiRequestNodeDataDriveFlit(input chiStruct chiStructHandle);

endtask 

task chiRequestNodeRespGetLcrd();

endtask

task chiRequestNodeRespDriveFlit(input chiStruct chiStructHandle);
endtask 


task chiRequestNodeSnpDriveLcrd(input int resourcePlane);//we are selecting the resource plane
endtask


task chiRequestNodeSnpGetFlit(output chiStruct chiStructHandle);
endtask

task chiRequestNodeDataDriveLcrd();
endtask


task chiRequestNodeDataGetFlit(output chiStruct chiStructHandle);
endtask

task chiRequestNodeRespDriveLcrd();
endtask


task chiRequestNodeRespGetFlit(output chiStruct chiStructHandle);
endtask


endinterface 

`endif 
