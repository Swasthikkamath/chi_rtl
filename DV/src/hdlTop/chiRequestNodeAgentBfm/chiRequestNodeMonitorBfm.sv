`ifndef CHIREQUESTNODEMONITORBFM_INCLUDED
`define CHIREQUESTNODEMONITORBFM_INCLUDED

interface chiRequestNodeMonitorBfm(chiInterface chiInterfaceHandle); // here define the ports in correct manner preferably use wire or logic data type //if there is going to be passive data type use wire (if there is no reset task which drives 'z
timeunit 1ns;
  timeprecision 1ps;
import chiGlobalsPkg::*;

clocking chiRequestNodeCb@(posedge chiInterfaceHandle.clk);
  default input #1step output #1step;
endclocking 

task chiRequestNodeReqGetLcrd();
  //drive activating signals + wait for lcrd 
endtask 

task chiRequestNodeReqMonitorFlit(output chiStruct chiStructHandle);
  
endtask 

task chiRequestNodeDataGetLcrd();

endtask 

task chiRequestNodeDataMonitorFlit(output chiStruct chiStructHandle);

endtask 

task chiRequestNodeRespGetLcrd();

endtask

task chiRequestNodeRespMonitorFlit(output chiStruct chiStructHandle);
endtask 


task chiRequestNodeSnpDriveLcrd();
endtask


task chiRequestNodeSnpMonitorFlit(output chiStruct chiStructHandle);
endtask

task chiRequestNodeDataDriveLcrd();
endtask


task chiRequestNodeRxDataMonitorFlit(output chiStruct chiStructHandle);
endtask

task chiRequestNodeRespDriveLcrd();
endtask


task chiRequestNodeRxRespMonitorFlit(output chiStruct chiStructHandle);
endtask


endinterface 

`endif 
