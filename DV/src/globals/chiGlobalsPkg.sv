`ifndef CHIGLOBALSPKG_INCLUDED
`define CHIGLOBALSPKG_INCLUDED

package chiGlobalsPkg;
parameter int NUMOFREQUESTNODE=2; // OR HAVE DEFINE 
parameter int NUMOFSUBORDINATENODE=2;
typedef enum bit[1:0]{RNF,RNI,RND}requestNodeTypeEnum;
typedef enum bit{SNF,SNI} subordinateNodeTypeEnum;
typedef struct{bit compile;}chiStruct;
typedef struct{bit compile;}chiCfgStruct;

endpackage 

`endif

