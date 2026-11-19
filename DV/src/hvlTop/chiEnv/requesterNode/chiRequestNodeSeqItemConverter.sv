`ifndef CHIREQUESTNODESEQITEMCONVERTER_INCLUDED
`define CHIREQUESTNODESEQITEMCONVERTER_INCLUDED

class chiRequestNodeSeqItemConverter extends uvm_object;
  `uvm_object_utils(chiRequestNodeSeqItemConverter)

  extern function new(string name="chiRequestNodeSeqItemConverter");
  extern static function void fromClassReqFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);  //can we have struct for each flit ?? or one global struct only use necessary field 
  //or struct cant be used as certain fields will overlap based on type of
  //transaction right how to counter that 
  
  extern static function void fromClassDataFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);  //or have all field in struct only touch fields needed and then use $isunknown to dertermine which to send in bfm that is also possible 

  extern static function void fromClassRespFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);

  extern static function void toClassDataFlit(input chiStruct chiStructHandle,inout chiRequestNodeTx chiRequestNodeTxHandle);

  extern static function void toClassRespFlit(input chiStruct chiStructHandle,input chiRequestNodeTx chiRequestNodeTxHandle);

  extern static function void toClassSnpFlit(input chiStruct chiStructHandle,input chiRequestNodeTx chiRequestNodeTxHandle);

endclass
function chiRequestNodeSeqItemConverter::new(string name="chiRequestNodeSeqItemConverter");
  super.new();
endfunction 

function void chiRequestNodeSeqItemConverter::fromClassReqFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);

endfunction 

function void chiRequestNodeSeqItemConverter::fromClassDataFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);
endfunction 

function void chiRequestNodeSeqItemConverter::fromClassRespFlit(input chiRequestNodeTx chiRequestNodeTxHandle,output chiStruct chiStructHandle);
endfunction 

function void chiRequestNodeSeqItemConverter::toClassDataFlit(input chiStruct chiStructHandle,inout chiRequestNodeTx chiRequestNodeTxHandle);
endfunction 

function void chiRequestNodeSeqItemConverter::toClassRespFlit(input chiStruct chiStructHandle,input chiRequestNodeTx chiRequestNodeTxHandle);
endfunction

function void chiRequestNodeSeqItemConverter::toClassSnpFlit(input chiStruct chiStructHandle,input chiRequestNodeTx chiRequestNodeTxHandle);
endfunction 

`endif 
