`ifndef CHISUBORDINATENODEAGENTCONFIG_INCLUDED
`define CHISUBORDINATENODEAGENTCONFIG_INCLUDED

class chiSubordinateNodeAgentConfig extends uvm_object;
  `uvm_object_utils(chiSubordinateNodeAgentConfig)
  
  int localProcessorCount;

  subordinateNodeTypeEnum subordinateNodeTypeEnumHandle;
  
  bit mainMemory; //have only one subordinate act as main mem

  int numOfTlbInfo;
 
  addressRangeTlbInfoStruct addressRangeTlbInfoStructHandle[];

  longint programBasedBaseAddress[bit[15:0]];

  uvm_active_passive_enum is_active;

  //should plan for other config property   
  extern function new(string name="chiSubordinateNodeAgentConfig");

endclass

function chiSubordinateNodeAgentConfig :: new(string name="chiSubordinateNodeAgentConfig");
  super.new(name);
endfunction 
`endif 
