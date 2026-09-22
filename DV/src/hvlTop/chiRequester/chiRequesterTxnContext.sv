// One in-flight request. Routers write the fields; the worker waits on
// the ping mailbox so a response that arrives before the wait is not lost.

typedef struct packed {
  chiNodeIdT srcId;
  logic [P_CRD_TYPE_W-1:0] pcrdType;
} chiPcrdKeyT;

class chiRequesterTxnContext;
  chiRequesterTx item;
  chiTxnIdT txnId;
  chiReqOpcodeE opcode;
  bit gotResp;
  bit gotDbid;
  bit retrySeen;
  bit retrySent;
  bit dataSent;
  int unsigned beatsLeft;
  logic [RESP_W-1:0] compResp;
  logic [511:0] data;
  chiNodeIdT homeId;
  logic [P_CRD_TYPE_W-1:0] pcrdType;
  chiTxnIdT dbId;
  mailbox #(int) ping;

  function new();
    ping = new();
    gotResp = 1'b0;
    gotDbid = 1'b0;
    retrySeen = 1'b0;
    retrySent = 1'b0;
    dataSent = 1'b0;
    beatsLeft = 0;
    compResp = RESP_I;
    data = '0;
    homeId = '0;
    pcrdType = '0;
    dbId = '0;
  endfunction
endclass
