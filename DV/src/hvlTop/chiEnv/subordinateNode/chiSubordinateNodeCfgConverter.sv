`ifndef CHISUBORDINATENODECFGCONVERTER_INCLUDED 
`define CHISUBORDINATENODECFGCONVERTER_INCLUDED

class chiSubordinateNodeCfgConverter extends uvm_object;
  `uvm_object_utils(chiSubordinateNodeCfgConverter)

  extern function new(string name="chiSubordinateNodeCfgConverter");
  extern static function void fromCfgClass(input chiSubordinateNodeAgentConfig chiSubordinateNodeAgentConfigHandle,output chiCfgStruct chiCfgStructHandle);
endclass

function chiSubordinateNodeCfgConverter::new(string name="chiSubordinateNodeCfgConverter");
  super.new(name);
endfunction 

function void chiSubordinateNodeCfgConverter::fromCfgClass(input chiSubordinateNodeAgentConfig chiSubordinateNodeAgentConfigHandle,output chiCfgStruct chiCfgStructHandle);

endfunction 

`endif 
