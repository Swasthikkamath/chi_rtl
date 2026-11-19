`ifndef CHISUBORDINATENODESEQITEMCONVERTER_INCLUDED
`define CHISUBORDINATENODESEQITEMCONVERTER_INCLUDED

class chiSubordinateNodeSeqItemConverter extends uvm_object;
  `uvm_object_utils(chiSubordinateNodeSeqItemConverter)

  extern function new(string name="chiSubordinateNodeSeqItemConverter");
  //or struct cant be used as certain fields will overlap based on type of
  //transaction right how to counter that 
  
  extern static function void fromClassDataFlit(input chiSubordinateNodeTx chiSubordinateNodeTxHandle,output chiStruct chiStructHandle);  //or have all field in struct only touch fields needed and then use $isunknown to dertermine which to send in bfm that is also possible 

  extern static function void fromClassRespFlit(input chiSubordinateNodeTx chiSubordinateNodeTxHandle,output chiStruct chiStructHandle);

  extern static function void toClassDataFlit(input chiStruct chiStructHandle,inout chiSubordinateNodeTx chiSubordinateNodeTxHandle);

  extern static function void toClassReqFlit(input chiStruct chiStructHandle,inout chiSubordinateNodeTx chiSubordinateTxHandle);
endclass
function chiSubordinateNodeSeqItemConverter::new(string name="chiSubordinateNodeSeqItemConverter");
  super.new();
endfunction 


function void chiSubordinateNodeSeqItemConverter::fromClassDataFlit(input chiSubordinateNodeTx chiSubordinateNodeTxHandle,output chiStruct chiStructHandle);
endfunction 

function void chiSubordinateNodeSeqItemConverter::fromClassRespFlit(input chiSubordinateNodeTx chiSubordinateNodeTxHandle,output chiStruct chiStructHandle);
endfunction 

function void chiSubordinateNodeSeqItemConverter::toClassDataFlit(input chiStruct chiStructHandle,inout chiSubordinateNodeTx chiSubordinateNodeTxHandle);
endfunction 

function void chiSubordinateNodeSeqItemConverter::toClassReqFlit(input chiStruct chiStructHandle,inout chiSubordinateNodeTx chiSubordinateTxHandle);
endfunction 
`endif 
