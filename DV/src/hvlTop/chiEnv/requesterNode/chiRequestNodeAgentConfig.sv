`ifndef CHIREQUESTNODEAGENTCONFIG_INCLUDED
`define CHIREQUESTNODEAGENTCONFIG_INCLUDED

class chiRequestNodeAgentConfig extends uvm_object;
  `uvm_object_utils(chiRequestNodeAgentConfig)
  int localProcessorCount=3;
  requestNodeTypeEnum requestNodeTypeEnumHandle;
  uvm_active_passive_enum is_active;
  /*bit[ADDRESSWIDTH-1:0] tlbBaseAddressRegister;
  bit[ADDRESSWIDTH-1:0] gptBaseAddressRegister;*/
 
  virtual chiRequestNodeDriverBfm chiRequestNodeDriverBfmHandle;
  virtual chiRequestNodeMonitorBfm chiRequestNodeMonitorBfmHandle;
  requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle[];
  
  samConfigureStruct chiRequestNodeSamConfigHandle[];
  int hnfNodeIdConfig[homeNodeTypeEnum][$] ='{HNF:'{8,1289,266,1035},HNI:'{140},MN:'{525}};
  int rnNodeId;
  //below is cache config info we are keeping it same for all lps but if required this info can be passed on to lp config and have different cache size for each lps 
  //
/*  bit[2:0] gptCacheGranuleSize;
  cacheSizeEnum gptCacheSize; //mention in terms of KB
  int gptNumOfWays;

  bit[2:0] tlbCacheGranuleSize = 3;
  cacheSizeEnum tlbCacheSize;
  int tlbNumOfWays;

  bit[2:0] dataCacheGranuleSize = 6;
  cacheSizeEnum dataCacheSize;
  int dataNumOfWays;*/
  //should plan for other config property   
  extern function new(string name="chiRequestNodeAgentConfig");
endclass

function chiRequestNodeAgentConfig :: new(string name="chiRequestNodeAgentConfig");
  super.new(name);
endfunction 
`endif 
