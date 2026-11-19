`ifndef CHIINTERFACE_INCLUDED
`define CHIINTERFACE_INCLUDED

interface chiInterface(input clk,input reset);
  timeunit 1ns;
  timeprecision 1ps;
  bit[3:0]qos;
  modport chiRequestNodeDriverModport(input qos,input clk);
  modport chiRequestNodeMonitorModport(output qos,input clk);
  modport chiSubordinateNodeDriverModport(input qos,input clk);
  modport chiSubordinateNodeMonitorModport(output qos,input clk);
endinterface 

`endif 
