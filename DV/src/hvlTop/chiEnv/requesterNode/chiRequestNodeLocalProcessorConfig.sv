`ifndef CHIREQUESTNODELOCALPROCESSORCONFIG_INCLUDED
`define CHIREQUESTNODELOCALPROCESSORCONFIG_INCLUDED

class requestNodeLocalProcessorConfig extends uvm_object;
  `uvm_object_utils(requestNodeLocalProcessorConfig)

  int numOfReads,numOfWrites;

  bit[2:0] gptCacheGranuleSize;
  cacheSizeEnum gptCacheSize; //mention in terms of KB
  int gptNumOfWays;
   
  bit[2:0] tlbCacheGranuleSize = 3;
  cacheSizeEnum tlbCacheSize;
  int tlbNumOfWays;
  
  bit[2:0] dataCacheGranuleSize = 6;
  cacheSizeEnum dataCacheSize;
  int dataNumOfWays;
 
  rand securityLevelEnum securityLevelHandle;
  
  exceptionLevelEnum exceptionLevelEnumHandle = guestOs;

  longint programBasedBaseAddress[bit[15:0]];

  extern function new(string name="requestNodeLocalProcessorConfig");

endclass

function requestNodeLocalProcessorConfig :: new(string name="requestNodeLocalProcessorConfig");
  super.new(name);
endfunction
`endif 
