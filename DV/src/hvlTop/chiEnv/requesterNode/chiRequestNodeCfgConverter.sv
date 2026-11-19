`ifndef CHIREQUESTNODECFGCONVERTER_INCLUDED 
`define CHIREQUESTNODECFGCONVERTER_INCLUDED

class chiRequestNodeCfgConverter extends uvm_object;
  `uvm_object_utils(chiRequestNodeCfgConverter)

  extern function new(string name="chiRequestNodeCfgConverter");
  extern static function void fromCfgClass(input chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle,output chiCfgStruct chiCfgStructHandle);
endclass

function chiRequestNodeCfgConverter::new(string name="chiRequestNodeCfgConverter");
  super.new(name);
endfunction 

function void chiRequestNodeCfgConverter::fromCfgClass(input chiRequestNodeAgentConfig chiRequestNodeAgentConfigHandle,output chiCfgStruct chiCfgStructHandle);

endfunction 

`endif 
