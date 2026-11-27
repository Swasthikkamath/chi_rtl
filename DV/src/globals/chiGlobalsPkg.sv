`ifndef CHIGLOBALSPKG_INCLUDED
`define CHIGLOBALSPKG_INCLUDED

package chiGlobalsPkg;
  
  parameter int NUMOFREQUESTNODE=5; // OR HAVE DEFINE 
  
  parameter int NUMOFSUBORDINATENODE=3;

  parameter int numOfHni = 1;

  parameter int numOfHnf = 4;;

  parameter int numOfMn = 1;

  parameter int NUMOFHOMENODE =  numOfHni + numOfHnf + numOfMn;
  
  parameter int ADDRESSWIDTH = 44;
  
  parameter int MAXGRANULESIZE= 6;

 parameter int NODEID_Width = 7; // Legal values 7 - 16
  parameter int ADDR_Width = 44; // Legal values 44 - 52
  parameter int DW = 128; // Data_Width Legal values - 128, 256, 512 
  parameter int DataCheck = 0; // 0 for zero or other value for DW/8
  parameter int Poison = 0; // 0 for zero or other value for DW/64


  parameter int M  = 0; // Legal values 0, 12, 15
    parameter int PB = 0; // Legal values 0, 4
    parameter int E  = 0; // Legal values 0, 16
    parameter int R  = 0; // Legal values 0, 16
    parameter bit S  = 0; // Legal values 0, 1
    parameter int Y  = 0; // Legal values 0, 4, 8, 12, 16, 24, 32

  // Use minimum width of 1 when the configured field width is 0
    localparam int MPAM_WIDTH   = (M  == 0) ? 1 : M;
    localparam int PBHA_WIDTH   = (PB == 0) ? 1 : PB;
    localparam int MECID_WIDTH  = (E  == 0) ? 1 : E;
    localparam int STREAM_WIDTH = (R  == 0) ? 1 : R;
    localparam int RSVDC_WIDTH  = (Y  == 0) ? 1 : Y;
        localparam int DataCheck_Width = (DataCheck == 0)? 1: DW/8;

  localparam int Poison_Width = (Poison == 0)? 1: DW/64; 
 
  parameter int pageSize = 4;//interms of kb

  parameter int level = (ADDRESSWIDTH - ($clog2(pageSize * 1024)))/($clog2(((pageSize * 1024)/8)));
  
  parameter longint ioAddressMapStartingAddress = 0;

  parameter longint ioAddressMapEndingAddress = 'd 1048576;

  parameter numOfProcess = 2;
  typedef enum bit[2:0]{
    secure,
    nonSecure,
    root,
    realm,
    systemAgent,
    nonSecureProtected
  }securityLevelEnum;
 
  typedef enum bit[3:0]{
    hyPervisorGuesOs=0,
    EL3 =4,
    guestOs =8,
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
 
  typedef enum bit[1:0]{
    HNF,
    HNI,
    MN
  }homeNodeTypeEnum;
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

  parameter longint MAIR = 64'h bb_88_4F_44_FF_08_04_00; 

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
    longint walkerLevelAddress[longint][level][$];
  }addressRangeTlbInfoStruct;

  // 10  (50)

  typedef struct{
    bit[ADDRESSWIDTH-1:0] physicalAddress;
    homeNodeTypeEnum homeNodeTypeEnumHandle;
  }samConfigureStruct;

  typedef struct{bit compile;}chiStruct;
  
  typedef struct{bit compile;}chiCfgStruct;

endpackage 

`endif

