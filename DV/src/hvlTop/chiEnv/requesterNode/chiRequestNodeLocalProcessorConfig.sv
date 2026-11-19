`ifndef CHIREQUESTNODELOCALPROCESSORCONFIG_INCLUDED
`define CHIREQUESTNODELOCALPROCESSORCONFIG_INCLUDED

class requestNodeLocalProcessorConfig extends uvm_object;
  `uvm_object_utils(requestNodeLocalProcessorConfig)

  int numOfReads,numOfWrites;
  extern function new(string name="requestNodeLocalProcessorConfig");

endclass

function requestNodeLocalProcessorConfig :: new(string name="requestNodeLocalProcessorConfig");
  super.new(name);
endfunction
`endif 
