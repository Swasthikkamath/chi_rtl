`ifndef CHIREQUESTNODELOCALPROCESSOR_INCLUDED 
`define CHIREQUESTNODELOCALPROCESSOR_INCLUDED 

class chiRequestNodeLocalProcessor extends uvm_object; //not a subclass as its just used to replicate a local processor in core 
  `uvm_object_utils(chiRequestNodeLocalProcessor) 

  logic[MAXGRANULESIZE-1:0]dataCache[][];
  logic[MAXGRANULESIZE-1:0]dataTagCache[][];
  bit dataValid[][];
  bit dirtyValid[][];

  logic[MAXGRANULESIZE-1:0]gptCache[][];
  logic[MAXGRANULESIZE]gptTagCache[][];
  bit gptValid[][];  

  logic[MAXGRANULESIZE-1:0]tlbCache[][][]; //or should we use struct is a option too but data which is obatined is 8 byte vector so preferably let it be vector ... part select to get the required info like asid or translation or shareability info
  logic[MAXGRANULESIZE]tlbTagCache[][][];
  bit tlbValid[][][];
  
  
  longint scrEL3,spsrEL3,ttbr1,mair;

  exceptionLevelEnum currentEl;//


  extern function new(string name="chiRequestNodeLocalProcessor");

  extern function void createCache(requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit[1:0]cacheType);

  extern function bit checkForBlock(longint physicalAddress,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,chiRequestNodeTx requestNodeTxHandle); //THIS ADDRESS SHOULD BE PHYSICAL ADDRESS REMEM THAT
  extern function void writeToBlock(longint physicalAddress,bit[MAXGRANULESIZE] data,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit writeThrough,bit[MAXGRANULESIZE-1:0] evictionData,bit evict,bit[ADDRESSWIDTH-1:0] evictionAddress,bit allocate);
  extern function void applyBootSetting(requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle);
  extern function longint  translateVirtualAddress(chiRequestNodeTx requestNodeTxHandle,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit hitOrMiss);
  extern function void checkForSecurityWorld(longint physicalAddress,chiRequestNodeTx requestNodeTxHandle,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit hitOrMiss,bit securityWorldMatch);
endclass

function void chiRequestNodeLocalProcessor :: checkForSecurityWorld(longint physicalAddress,chiRequestNodeTx requestNodeTxHandle,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit hitOrMiss,bit securityWorldMatch);
  int minIndex = requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize;
  int setStartingIndex = minIndex;
  int setEndingIndex = setStartingIndex + ($size(gptCache[0],1))-1;
  int tagStartingIndex = setEndingIndex +1;
  int tagEndingIndex = (2**(requestNodeLocalProcessorConfigHandle.gptCacheGranuleSize))-1;
  int set;
  longint tag;
  int setIndexCounter;
  int tagIndexCounter;
 
  for(int i=setStartingIndex;i<= setEndingIndex;i++,setIndexCounter++) begin 
    set[setIndexCounter] = physicalAddress[i];
  end 

  for(int i=tagStartingIndex ;i <= tagEndingIndex ;i++,tagIndexCounter++)begin 
     tag[tagIndexCounter] = physicalAddress[i];
  end 

  for(int ways = 0 ; ways <(requestNodeLocalProcessorConfigHandle.gptNumOfWays);ways++) begin 
    if(gptValid[set][ways]) begin 
      if(gptTagCache[set][ways]== tag)begin 
        hitOrMiss = 1;
        if(requestNodeTxHandle.pas == gptCache[set][tag])begin 
          securityWorldMatch=1;
        end 
        else begin 
          securityWorldMatch=0;
        end 
      end
      return;
    end 
  end 

endfunction
function longint  chiRequestNodeLocalProcessor :: translateVirtualAddress(chiRequestNodeTx requestNodeTxHandle,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit hitOrMiss);
  int minIndex = requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize;
  int setStartingIndex = minIndex;
  int setEndingIndex = setStartingIndex + ($size(tlbCache[0],1))-1;
  int tagStartingIndex = setEndingIndex +1;
  int tagEndingIndex = (2**(requestNodeLocalProcessorConfigHandle.tlbCacheGranuleSize))-1;
  int set;
  longint tag;
  int setIndexCounter;
  int tagIndexCounter;
  longint physicalAddress = requestNodeTxHandle.addr;
 
  for(int i=setStartingIndex;i<= setEndingIndex;i++,setIndexCounter++) begin 
    set[setIndexCounter] = physicalAddress[i];
  end 

  for(int i=tagStartingIndex ;i <= tagEndingIndex ;i++,tagIndexCounter++)begin 
     tag[tagIndexCounter] = physicalAddress[i];
  end 

  for(int ways=0;ways< requestNodeLocalProcessorConfigHandle.tlbNumOfWays ; ways++)begin 
    if(tlbValid[requestNodeTxHandle.selectedAsid][set][ways])begin 
      if(tlbTagCache[requestNodeTxHandle.selectedAsid][set][ways] == tag)begin 
        hitOrMiss = 1;
        return tlbCache[requestNodeTxHandle.selectedAsid][set][ways];
      end 
    end 
  end 
  hitOrMiss =0;
  
endfunction 


function void chiRequestNodeLocalProcessor::applyBootSetting(requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle);
  currentEl = EL3;
  scrEL3[62] = requestNodeLocalProcessorConfigHandle.securityLevelHandle[1];
  scrEL3[0] = requestNodeLocalProcessorConfigHandle.securityLevelHandle[0];
  spsrEL3 = requestNodeLocalProcessorConfigHandle.exceptionLevelHandle; 
  mair = MAIR;;
  tlbCache.delete();
  dataCache.delete();
  gptCache.delete();
  tlbTagCache.delete();
  dataTagCache.delete();
  dataValid.delete();
  dirtyValid.delete();
  tlbValid.delete();
  currentEl = {scrEL3[62],scrEL3[0]};
endfunction 

function chiRequestNodeLocalProcessor :: new(string name="chiRequestNodeLocalProcessor");
  super.new(name);
endfunction 

function void chiRequestNodeLocalProcessor :: createCache(requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit[1:0]cacheType);
  int setSize;
  
  if(cacheType == 0 )begin //creation of gpt cache  
    setSize = ( requestNodeLocalProcessorConfigHandle.gptCacheSize/(requestNodeLocalProcessorConfigHandle.gptNumOfWays *(2**( requestNodeLocalProcessorConfigHandle.gptCacheGranuleSize))));
    gptCache = new[setSize];
    foreach(gptCache[set]) begin 
      gptCache[set] = new[requestNodeLocalProcessorConfigHandle.gptNumOfWays];
    end 
    //each element in the ways will be having width of MAXGRANULESIZE but use only max granule config size only 
  end 
  else if (cacheType == 1 ) begin  // creation of tlb cache
    setSize = ( requestNodeLocalProcessorConfigHandle.tlbCacheSize/(requestNodeLocalProcessorConfigHandle.tlbNumOfWays *(2**( requestNodeLocalProcessorConfigHandle.tlbCacheGranuleSize))));
    tlbCache = new[256];
    tlbTagCache = new[256];
    tlbValid = new[256];
    foreach(tlbCache[i])
      tlbCache[i]= new[setSize];
    foreach(tlbTagCache[i])
      tlbTagCache[i] = new[setSize];
    foreach(tlbValid[i])
      tlbValid[i] = new[setSize];
    foreach(tlbCache[asid,set]) begin 
      tlbCache[asid][set] = new[requestNodeLocalProcessorConfigHandle.tlbNumOfWays];
      tlbTagCache[asid][set] = new[requestNodeLocalProcessorConfigHandle.tlbNumOfWays];
      tlbValid[asid][set] = new[requestNodeLocalProcessorConfigHandle.tlbNumOfWays];
    end 
  end 
  else begin //creation of data cache 
    setSize = ( requestNodeLocalProcessorConfigHandle.dataCacheSize/(requestNodeLocalProcessorConfigHandle.dataNumOfWays *(2**( requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize))));
    dataCache = new[setSize];
    dataTagCache = new[setSize];
    dataValid = new[setSize];
    dirtyValid = new[setSize];

    foreach(dataCache[set]) begin 
      dataCache[set] = new[requestNodeLocalProcessorConfigHandle.dataNumOfWays];
      dataTagCache[set] = new[requestNodeLocalProcessorConfigHandle.dataNumOfWays];
      dataValid[set] = new[requestNodeLocalProcessorConfigHandle.dataNumOfWays];
      dirtyValid[set] = new[requestNodeLocalProcessorConfigHandle.dataNumOfWays];
    end
  end 
endfunction 

function bit chiRequestNodeLocalProcessor :: checkForBlock(longint physicalAddress,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,chiRequestNodeTx requestNodeTxHandle); //keep write read sep as eviction and all should be taken care of so preferably sep function is better 
  int minIndex = requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize;
  int setStartingIndex = minIndex;
  int setEndingIndex = setStartingIndex + ($size(dataCache[0],1))-1;
  int tagStartingIndex = setEndingIndex +1;
  int tagEndingIndex = (2**(requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize))-1;
  int set;
  longint tag;
  int setIndexCounter;
  int tagIndexCounter;
 
  ttbr1[63:48] = requestNodeTxHandle.selectedAsid;
  ttbr1[47:1] = requestNodeLocalProcessorConfigHandle.programBasedBaseAddress[requestNodeTxHandle.selectedAsid];
  for(int i=setStartingIndex;i<= setEndingIndex;i++,setIndexCounter++) begin 
    set[setIndexCounter] = physicalAddress[i];
  end 

  for(int i=tagStartingIndex ;i <= tagEndingIndex ;i++,tagIndexCounter++)begin 
     tag[tagIndexCounter] = physicalAddress[i];
  end 

  for(int way=0;way<requestNodeLocalProcessorConfigHandle.dataNumOfWays;way++)begin 
    if(dataValid[set][way] == 1) begin 
      if(tag == dataTagCache[set][way]) begin 
        return 1;
      end 
    end 
  end 
  return 0;
endfunction 

function void  chiRequestNodeLocalProcessor :: writeToBlock (longint physicalAddress,bit[MAXGRANULESIZE-1:0]data,requestNodeLocalProcessorConfig requestNodeLocalProcessorConfigHandle,bit writeThrough,bit[MAXGRANULESIZE-1:0] evictionData,bit evict,bit[ADDRESSWIDTH-1:0] evictionAddress,bit allocate);
  int minIndex = requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize;
  int setStartingIndex = minIndex;
  int setEndingIndex = setStartingIndex + ($size(dataCache[0],1))-1;
  int tagStartingIndex = setEndingIndex +1;
  int tagEndingIndex = (2**(requestNodeLocalProcessorConfigHandle.dataCacheGranuleSize))-1;
  int set;
  longint tag;
  int setIndexCounter;
  int tagIndexCounter;
  int dirtyValidCounter;
  int validCounter;
  int way;
  for(int i=setStartingIndex;i<= setEndingIndex;i++,setIndexCounter++) begin 
    set[setIndexCounter] = physicalAddress[i];
  end 

  for(int i=tagStartingIndex ;i <= tagEndingIndex ;i++,tagIndexCounter++)begin 
     tag[tagIndexCounter] = physicalAddress[i];
  end 

  for(int way=0;way<requestNodeLocalProcessorConfigHandle.dataNumOfWays;way++)begin 
    if(dataValid[set][way] == 1)begin 
      validCounter++;
    end 
  end 
 
  for(int way=0;way<requestNodeLocalProcessorConfigHandle.dataNumOfWays;way++)begin 
    if(dirtyValid[set][way] == 1)begin 
      dirtyValidCounter++;
    end 
  end 
  
  if(validCounter == requestNodeLocalProcessorConfigHandle.dataNumOfWays)begin
    for(int j=0;j<requestNodeLocalProcessorConfigHandle.dataNumOfWays;j++)begin 
      if(dirtyValid[set][way] == 1)begin 
        //writ to this and evict the data 
        int dataOffset;
        for(int i=0 ; i < (requestNodeLocalProcessorConfigHandle.dataNumOfWays) ;i++ )begin 
          dataOffset[i] = physicalAddress[i];
        end  
        //befpre write we have to see the policy followed too 
        //and /4 is kinda like block size from cache to core 
        for(int i=0;i<4;i++)
          dataCache[set][way][dataOffset+i] = data[8*i +:8];
      end 
    end 
  end 
  else begin
    for(int way=0;way<requestNodeLocalProcessorConfigHandle.dataNumOfWays;way++)begin 
      if(dataValid[set][way] != 1)begin 
         // now write here no eviction
      end 
    end   
  end 

endfunction
`endif 
