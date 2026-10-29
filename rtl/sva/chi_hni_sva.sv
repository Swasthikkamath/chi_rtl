// HN-I assertions.
//
//   HNI_INPUTS_ALWAYS_READY  RSP and DAT are always accepted, so the HN-I
//       never makes one channel wait on another.
//   HNI_DOWNSTREAM_OWN_IDS  every request to an SN-I carries the HN-I's
//       SrcID and an entry index as TxnID, never a Requester's; a PCrdReturn
//       carries TxnID zero (IHI 0050H B2.4.2).
//   HNI_DOWNSTREAM_FIELDS_LEGAL  SnpAttr and ExpCompAck are zero, and Order
//       is never Request accepted (IHI 0050H B2.8.6, Table B2.9).
//   HNI_ENDPOINT_ORDER_RESPECTED  an Endpoint-ordered request goes
//       downstream only when no older ordered request from its source is
//       still unaccepted (IHI 0050H B2.7.5).
//   HNI_OWO_WRITE_AFTER_COMPACK  a write with ExpCompAck goes downstream only
//       after its CompAck (IHI 0050H B2.7.5.3).
//   HNI_RECEIPT_BEFORE_DATA  an ordered read's CompData never precedes its
//       ReadReceipt.
//   HNI_DOWNSTREAM_PAS_PRESERVED  a request to an SN-I carries the PAS of
//       the request it serves (IHI 0050H B2.8.2).
//
// Covers: concurrent transactions, a same-line waiter, an Endpoint-ordered
// request held back, a downstream RetryAck, an OWO write, a forwarded atomic,
// a configuration write, RetryAck and PCrdGrant to a Requester.
module chi_hni_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0,
  parameter int unsigned DEPTH = 1,
  parameter int unsigned IDX_W = 1,
  parameter int unsigned KEY_W = 1,
  parameter int unsigned LINE_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic rspInReady,
  input logic datInReady,
  input logic reqOutValid,
  input chi_pkg::chi_noc_flit_t reqOutFlit,
  input logic [DEPTH-1:0] posActive,
  input logic [DEPTH-1:0] posStarted,
  input logic [DEPTH-1:0][DEPTH-1:0] posOlder,
  input logic [DEPTH-1:0][KEY_W-1:0] posKey,
  input chi_pkg::chi_order_e [DEPTH-1:0] posOrder,
  input logic [DEPTH-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] posRequester,
  input logic [DEPTH-1:0] eMayStart,
  input logic [DEPTH-1:0] eEndpointClear,
  input logic [DEPTH-1:0] eOrdered,
  input logic [DEPTH-1:0] eAccepted,
  input logic [DEPTH-1:0] eOwoWrite,
  input logic [DEPTH-1:0] eCompAckOwed,
  input logic [DEPTH-1:0] eReceiptOwed,
  input logic [DEPTH-1:0] dnStartValid,
  input chi_hnf_pkg::chi_hnf_dn_e [DEPTH-1:0] dnStartKind,
  input logic [DEPTH-1:0] dnResend,
  input logic datEntrySend,
  input logic [IDX_W-1:0] datEntry,
  input logic cfgApplyValid,
  input logic retryHandshake,
  input logic rspGrantSend
);
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  chi_req_flit_t downstream;

  always_comb begin
    downstream = unpackReqFlit(CFG, reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
  end

  HNI_INPUTS_ALWAYS_READY: assert property (
    @(posedge clk) disable iff (!resetn)
    rspInReady && datInReady);

  HNI_DOWNSTREAM_OWN_IDS: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid
      |-> (downstream.srcId == HN_NODE_ID)
          && ((downstream.opcode == REQ_PCRD_RETURN)
              ? (downstream.txnId == '0)
              : (int'(downstream.txnId) < DEPTH)));

  HNI_DOWNSTREAM_FIELDS_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid
      |-> !downstream.snpAttrOrDoDwt && !downstream.expCompAck
          && (downstream.order != ORDER_REQUEST_ACCEPTED));

  for (genvar i = 0; i < DEPTH; i++) begin : per_entry
    logic olderOrderedPending;
    always_comb begin
      olderOrderedPending = 1'b0;
      for (int unsigned j = 0; j < DEPTH; j++)
        if ((j != i) && posActive[j] && posOlder[i][j] && eOrdered[j]
            && !eAccepted[j] && (posRequester[j] == posRequester[i]))
          olderOrderedPending = 1'b1;
    end

    HNI_ENDPOINT_ORDER_RESPECTED: assert property (
      @(posedge clk) disable iff (!resetn)
      dnStartValid[i] && (dnStartKind[i] != HNF_DN_CMO)
      && (posOrder[i] == ORDER_ENDPOINT)
        |-> !olderOrderedPending);

    HNI_OWO_WRITE_AFTER_COMPACK: assert property (
      @(posedge clk) disable iff (!resetn)
      dnStartValid[i] && (dnStartKind[i] == HNF_DN_WRITE) && eOwoWrite[i]
        |-> !eCompAckOwed[i]);
  end

  HNI_DOWNSTREAM_PAS_PRESERVED: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && (downstream.opcode != REQ_PCRD_RETURN)
    && (int'(downstream.txnId) < DEPTH)
      |-> (downstream.pas
           == chi_pas_e'(posKey[downstream.txnId][KEY_W-1:LINE_W])));

  HNI_RECEIPT_BEFORE_DATA: assert property (
    @(posedge clk) disable iff (!resetn)
    datEntrySend |-> !eReceiptOwed[datEntry]);

  HNI_CONCURRENT_TRANSACTIONS: cover property (
    @(posedge clk) disable iff (!resetn)
    !$onehot0(posStarted));

  HNI_SAME_LINE_WAITER: cover property (
    @(posedge clk) disable iff (!resetn)
    (posActive & ~posStarted & ~eMayStart) != '0);

  HNI_ENDPOINT_ORDER_WAIT: cover property (
    @(posedge clk) disable iff (!resetn)
    (posStarted & ~eEndpointClear) != '0);

  HNI_DOWNSTREAM_RETRY: cover property (
    @(posedge clk) disable iff (!resetn)
    dnResend != '0);

  HNI_OWO_WRITE: cover property (
    @(posedge clk) disable iff (!resetn)
    (dnStartValid & eOwoWrite) != '0);

  HNI_ATOMIC_FORWARDED: cover property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && isAtomicOpcode(downstream.opcode));

  HNI_CONFIG_WRITE: cover property (
    @(posedge clk) disable iff (!resetn)
    cfgApplyValid);

  HNI_RETRY_ACK_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    retryHandshake);

  HNI_PCRD_GRANT_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    rspGrantSend);
endmodule

// The HN-I's own SAM maps every address to its SN-I and is never updated,
// so a request outside the configuration window that the Requester-side SAM
// did not refuse, in a legal PAS, always finds an SN-I.
module chi_hni_decode_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input logic clk,
  input logic resetn,
  input logic reqInValid,
  input logic dropRequest,
  input logic configAccess,
  input chi_pkg::chi_noc_err_e decodeErr,
  input chi_pkg::chi_pas_e pas,
  input logic sniKnown
);
  HNI_REQUEST_FINDS_SNI: assert property (
    @(posedge clk) disable iff (!resetn)
    (reqInValid && !dropRequest && !configAccess
     && (decodeErr == chi_pkg::NOC_ERR_NONE) && chi_pkg::pasLegal(CFG, pas))
      |-> sniKnown);
endmodule

bind chi_hni_top chi_hni_decode_sva #(
  .CFG(CFG)
) chi_hni_decode_assertions (
  .clk(clk),
  .resetn(resetn),
  .reqInValid(reqInValid),
  .dropRequest(dropRequest),
  .configAccess(configAccess),
  .decodeErr(reqInFlit.decodeErr),
  .pas(incomingReq.pas),
  .sniKnown(sniKnown)
);

bind chi_hni_top chi_hni_sva #(
  .CFG(CFG),
  .HN_NODE_ID(HN_NODE_ID),
  .DEPTH(DEPTH),
  .IDX_W(IDX_W),
  .KEY_W(KEY_W),
  .LINE_W(LINE_W)
) chi_hni_assertions (
  .clk(clk),
  .resetn(resetn),
  .rspInReady(rspInReady),
  .datInReady(datInReady),
  .reqOutValid(reqOutValid),
  .reqOutFlit(reqOutFlit),
  .posActive(posActive),
  .posStarted(posStarted),
  .posOlder(posOlder),
  .posKey(posKey),
  .posOrder(posOrder),
  .posRequester(posRequester),
  .eMayStart(eMayStart),
  .eEndpointClear(eEndpointClear),
  .eOrdered(eOrdered),
  .eAccepted(eAccepted),
  .eOwoWrite(eOwoWrite),
  .eCompAckOwed(eCompAckOwed),
  .eReceiptOwed(eReceiptOwed),
  .dnStartValid(dnStartValid),
  .dnStartKind(dnStartKind),
  .dnResend(dnResend),
  .datEntrySend(datEntrySend),
  .datEntry(datEntry),
  .cfgApplyValid(cfgApplyValid),
  .retryHandshake(retryHandshake),
  .rspGrantSend(rspGrantSend)
);
