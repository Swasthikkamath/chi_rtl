`ifndef CHIREQUESTNODETX_INCLUDED
`define CHIREQUESTNODETX_INCLUDED

class chiRequestNodeTx extends uvm_sequence_item;
  `uvm_object_utils(chiRequestNodeTx) 
 //define all the properties if needed use field macros for automation   
  extern function new(string name="chiRequestNodeTx");
  bit writeOrRead;
  int LPID; 
 int pas;
  bit[MAXGRANULESIZE-1:0] data;
  longint addr;
  bit[15:0]selectedAsid;
  //REQ Flit

bit [3:0]     QoS;

bit [NODEID_Width-1:0]    TgtID;
bit [NODEID_Width-1:0]    SrcID;
bit [11:0]      TxnID;

bit [NODEID_Width-1:0]    ReturnNID;
bit [NODEID_Width-1:0]    StashNID;

bit [6:0]     Data_Target; // {(NodeID_Width - 7)’b0, DataTarget[6:0]}

bit       StashNIDValid;
bit       Endian;
bit       Deep;
bit       PrefetchTgtHint;

bit [11:0]      ReturnTxnID;

// {6’b0, StashLPIDValid, StashLPID[4:0]}
bit         StashLPIDValid; 
bit [4:0]     StashLPID; 

bit [6:0]       Opcode;

bit         MultiReq;
bit [5:0]     NumReq; 

bit [2:0]     Size; //{3’b0, Size}
bit [ADDR_Width-1:0]    Addr;

bit [2:0]     PAS;
bit                     LikelyShared;
bit                     AllowRetry;
bit [1:0]     Order;
bit [3:0]     PCrdType;
bit [3:0]       MemAttr;
bit                     SnpAttr;
bit                     DoDWT;

bit [7:0]     PGroupID;
bit [7:0]     StashGroupID;
bit [7:0]     TagGroupID;

bit [4:0]     LPID; //{3’b0, LPID[4:0]}

bit       Excl;
bit       SnoopMe;
bit       CAH;
bit       ExpCompAck;

bit [1:0]     TagOp;
bit       TraceTag;

bit [MPAM_WIDTH-1:0]    MPAM;
bit [PBHA_WIDTH-1:0]    PBHA;
bit [MECID_WIDTH-1:0]   MECID;
bit [STREAM_WIDTH-1:0]          StreamID;
bit         SecSID1;

bit [RSVDC_WIDTH-1:0]   RSVDC;
 
 
//Data Flit

bit [3:0]     QoS;

bit [NODEID_Width-1:0]    TgtID;
bit [NODEID_Width-1:0]    SrcID;
bit [11:0]      TxnID;
bit [NODEID_Width-1:0]    HomeNID;

//{(NodeID_Width - 5)’b0, MismatchedMECID, PBHA[3:0]}
bit       MismatchedMECID; 
bit [3:0]     PBHA; 

bit [3:0]     Opcode;

bit [1:0]               RespErr;
bit [2:0]               Resp;

bit [7:0]               DataSource;
bit [2:0]     FwdState; //{5’b0,FwdState[2:0]}

bit         DataPull;
bit [2:0]     CBusy;

bit [MECID_WIDTH-1:0]   MECID;
bit [11:0]      DBID; //{4’b0, DBID[11:0]}

bit [1:0]               CCID;
bit [1:0]               DataID;
bit [5:0]           CacheLineID;
bit [1:0]       TagOp;

bit [DW/32-1:0]     Tag;
bit [DW/128-1:0]    TU;

bit         TraceTag;
bit       CAH;
bit [1:0]     NumDat;
bit       Replicate;

bit [RSVDC_WIDTH-1:0]     RSVDC;

bit [DW/8-1:0]      BE;
bit [DW-1:0]        Data;

bit [DataCheck_Width-1:0]     DataCheck; //0 or DW/8 = 16, 32, 64
bit [Poison_Width-1:0]    Poison; // 0 or DW/64 = 2, 4, 8
 
 
//Response Flit

bit [3:0]     QoS;

bit [NODEID_Width-1:0]    TgtID;
bit [NODEID_Width-1:0]    SrcID;
bit [11:0]      TxnID;

bit [4:0]               Opcode;

bit [1:0]               RespErr;
bit [2:0]               Resp;

bit [2:0]               FwdState;
bit                 DataPull; // {2'b0, DataPull}
bit [2:0]               CBusy;

bit [11:0]          DBID;

bit [7:0]         PGroupID; // {4’b0, PGroupID[7:0]}
bit [7:0]         StashGroupID; // {4’b0, StashGroupID[7:0]}
bit [7:0]         TagGroupID; // {4’b0, TagGroupID[7:0]}

bit [3:0]         PCrdType;
bit [1:0]         TagOp;
bit           TraceTag;
bit [5:0]         CacheLineID;
 
 
//Snoop Flit

bit [3:0]     QoS;

bit [NODEID_Width-1:0]    SrcID;
bit [11:0]      TxnID;
bit [NODEID_Width-1:0]    FwdNID;

bit [3:0]               PBHA; // {(NodeID_Width - 4)’0, PBHA[3:0]}

bit [11:0]          FwdTxnID;

// {6’b0, StashLPIDValid, StashLPID[4:0]}
bit                     StashLPIDValid;
bit [4:0]               StashLPID;

bit [7:0]         VMIDExt; // {4’b0, VMIDExt[7:0]}

bit [4:0]               Opcode;

bit [(ADDR_Width-3)-1:0]      Addr; // 41 to 49

bit [2:0]       PAS;
bit                     DoNotGoToSD;
bit                     RetToSrc;
bit                     TraceTag;

bit [MPAM_WIDTH-1:0]      MPAM;
bit [MECID_WIDTH-1:0]   MECID;

 
 
 
 
 
 
 
 
endclass

function chiRequestNodeTx :: new(string name="chiRequestNodeTx");
  super.new(name);
endfunction 
`endif 
