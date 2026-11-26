`ifndef CHIGLOBALSPKG_INCLUDED
`define CHIGLOBALSPKG_INCLUDED

package chiGlobalsPkg;
  
  parameter int NUMOFREQUESTNODE=2; // OR HAVE DEFINE 
  
  parameter int NUMOFSUBORDINATENODE=2;
  
  parameter int ADDRESSWIDTH = 44;
  
  parameter int MAXGRANULESIZE= 6;
  
  typedef enum bit[2:0]{
    secure,
    nonSecure,
    root,
    realm,
    systemAgent,
    nonSecureProtected
  }securityLevelEnum;
 
  typedef enum bitp[3:0]{
    hyPervisorGuesOs=0,
    EL3 =4,
    guestOs =8;
    hypervisor =12 
  }exceptionLevelEnum;
  typedef enum bit[1:0]{
    RNF,
    RNI,
    RND
  }requestNodeTypeEnum;
  
  typedef enum bit{
    SNF,
    SNI
  } subordinateNodeTypeEnum;
 
  typedef enum int {
    FOUREKILOBYTES,
    SIXTEENKILOBYTES,
    SIXTYFOUREKILOBUTES,
    TWOMEGABYTES,
    THIRTYTWOMEGABYTES,
    FIVEHUNDREADTWELFMEGABYTES,
    ONEGIGABYTES,
    SIXTEENGIGABYTES,
    SIXTYFOUREGIGABYTES,
    FIVEHUNDREADTWELFGIGABYTES
  }cacheSizeEnum;
  
  typedef struct packed {
    bit reserved1;
    bit[3:0]PBHA;
    bit[6:0]reserved2;
    bit DBM;
    bit [2:0]reserved3;
    bit NG;
    bit reserved4;
    bit SH;
    bit[1:0]reserved5;
    bit NS;
    bit[2:0]ATTRINDX; //is used to determine the memattr using mair register 
    bit TYPE;
    bit VALID;
  }tlbConfigStruct;

  typedef struct{
    bit[ADDRESSWIDTH-1:0]startAddress;
    bit[ADDRESSWIDTH-1:0]endAddress;
    tlbConfigStruct tlbConfigStructHandle;
  }addressRangeTlbInfoStruct;

  typedef struct{bit compile;}chiStruct;
  
  typedef struct{bit compile;}chiCfgStruct;

endpackage 

`endif

