// One request being answered. Contexts are keyed by the DBID this
// subordinate allocated, not by the requester TxnID, because two
// sources can reuse a TxnID. DAT and CompAck mailboxes keep a flit
// that arrives before the worker waits.

typedef struct packed {
  chiNodeIdT srcId;
  logic [P_CRD_TYPE_W-1:0] pcrdType;
} chiSubordinatePcrdKeyT;

class chiSubordinateTxnContext;
  chiReqFlitT req;
  chiTxnIdT dbId;
  int unsigned beatsLeft;
  logic [511:0] data;
  logic [63:0] be;
  bit cancelled;
  bit compAckSeen;
  mailbox #(chiDatFlitT) datMb;
  mailbox #(chiRspFlitT) ackMb;

  function new();
    datMb = new();
    ackMb = new();
    beatsLeft = 0;
    data = '0;
    be = '0;
    cancelled = 1'b0;
    compAckSeen = 1'b0;
    dbId = '0;
  endfunction
endclass
