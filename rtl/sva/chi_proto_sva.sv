// HN-F protocol assertions.
//
//   *_STABLE_UNDER_BACKPRESSURE  a presented flit holds until taken; the
//       REQ input check is the assumption the Home makes of the fabric.
//   DOWNSTREAM_OPCODE_LEGAL  every request to the SN-F is one the Home may
//       send it: ReadNoSnp, WriteNoSnpFull, WriteNoSnpPtl, a forwarded CMO,
//       or PCrdReturn (IHI 0050H B2.3.9).
//   DOWNSTREAM_FIELDS_LEGAL  Order is at most Request accepted, SnpAttr and
//       ExpCompAck are zero (IHI 0050H Table B2.9, B2.8.6).
//   COMPDATA_RESP_LEGAL  CompData carries only I, SC, UC, UD_PD or SD_PD
//       (IHI 0050H Table B4.27).
//   WRITE_COMPLETION_RESP_ZERO  Comp and CompDBIDResp carry Resp zero except
//       the OK/Unsupported answer to WriteNoSnpDef (IHI 0050H B4.5.1.3).
//   PCRD_GRANT_FIELDS_UNUSED  PCrdGrant carries no TxnID and no DBID
//       (IHI 0050H B2.5.5).
//   RETRY_ACK_GRANT_MUTUALLY_EXCLUSIVE  one RSP push per cycle.
//   NO_COMPLETION_WHILE_SNOOPING  an entry never completes while one of its
//       snoops is outstanding (IHI 0050H B4.11.2).
//   RECEIPT_BEFORE_DATA  an ordered read's CompData never precedes its
//       ReadReceipt.
module chi_proto_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned POS_DEPTH = 1,
  parameter int unsigned POS_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic reqInValid,
  input logic reqInReady,
  input chi_pkg::chi_noc_flit_t reqInFlit,
  input logic reqOutValid,
  input logic reqOutReady,
  input chi_pkg::chi_noc_flit_t reqOutFlit,
  input logic rspOutValid,
  input logic rspOutReady,
  input chi_pkg::chi_noc_flit_t rspOutFlit,
  input logic snpOutValid,
  input logic snpOutReady,
  input chi_pkg::chi_noc_flit_t snpOutFlit,
  input logic datOutValid,
  input logic datOutReady,
  input chi_pkg::chi_noc_flit_t datOutFlit,
  input logic retryHandshake,
  input logic rspGrantSend,
  input logic rspEntrySend,
  input logic [POS_W-1:0] rspEntry,
  input logic datEntrySend,
  input logic [POS_W-1:0] datEntry,
  input logic datEntryToPull,
  input logic [POS_DEPTH-1:0] eSnpDone,
  input logic [POS_DEPTH-1:0] eCompReady,
  input logic [POS_DEPTH-1:0] eCompIsData,
  input logic [POS_DEPTH-1:0] eReceiptOwed,
  input logic [POS_DEPTH-1:0] eCompOwed,
  input logic [POS_DEPTH-1:0] posActive,
  input logic [POS_DEPTH-1:0] posStarted,
  input logic sfVictimValid,
  input logic atomicValid,
  input logic snpIssueFire
);
  import chi_pkg::*;

  chi_req_flit_t downstream;
  chi_rsp_flit_t response;
  chi_dat_flit_t data;

  always_comb begin
    downstream = unpackReqFlit(CFG, reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    response = unpackRspFlit(CFG, rspOutFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    data = unpackDatFlit(CFG, datOutFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
  end

  REQ_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqInValid && !reqInReady |=> reqInValid && $stable(reqInFlit));

  REQ_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && !reqOutReady |=> reqOutValid && $stable(reqOutFlit));

  RSP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && !rspOutReady |=> rspOutValid && $stable(rspOutFlit));

  SNP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    snpOutValid && !snpOutReady |=> snpOutValid && $stable(snpOutFlit));

  DAT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    datOutValid && !datOutReady |=> datOutValid && $stable(datOutFlit));

  DOWNSTREAM_OPCODE_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid
      |-> downstream.opcode inside {
            REQ_READ_NO_SNP, REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
            REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP,
            REQ_CLEAN_INVALID_STORAGE, REQ_PCRD_RETURN});

  DOWNSTREAM_FIELDS_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid
      |-> ((downstream.order == ORDER_NONE)
           || (downstream.order == ORDER_REQUEST_ACCEPTED))
          && !downstream.snpAttrOrDoDwt && !downstream.expCompAck);

  COMPDATA_RESP_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    datOutValid && (data.opcode == DAT_COMP_DATA)
      && (data.respErr != RESP_ERR_NDERR)
      |-> data.resp inside {RESP_I, RESP_SC, RESP_UC_UD, RESP_UD_PD,
                            RESP_SD_PD});

  WRITE_COMPLETION_RESP_ZERO: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && (response.opcode == RSP_COMP_DBID_RESP)
      |-> (response.resp == RESP_I) || (response.resp == RESP_SC));

  PCRD_GRANT_FIELDS_UNUSED: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && (response.opcode == RSP_PCRD_GRANT)
      |-> (response.txnId == '0) && (response.dbIdOrGroupId == '0));

  RETRY_ACK_GRANT_MUTUALLY_EXCLUSIVE: assert property (
    @(posedge clk) disable iff (!resetn)
    $onehot0({retryHandshake, rspGrantSend, rspEntrySend}));

  NO_COMPLETION_WHILE_SNOOPING: assert property (
    @(posedge clk) disable iff (!resetn)
    (rspEntrySend && eCompReady[rspEntry] && !eCompIsData[rspEntry])
      || (datEntrySend && !datEntryToPull)
      |-> eSnpDone[rspEntrySend ? rspEntry : datEntry]);

  RECEIPT_BEFORE_DATA: assert property (
    @(posedge clk) disable iff (!resetn)
    datEntrySend && !datEntryToPull |-> !eReceiptOwed[datEntry]);

  // Two different locations make progress at once.
  CONCURRENT_TRANSACTIONS: cover property (
    @(posedge clk) disable iff (!resetn)
    !$onehot0(posStarted));

  // A request is held back while an older one for its location runs.
  SAME_LOCATION_WAITER: cover property (
    @(posedge clk) disable iff (!resetn)
    (posActive & ~posStarted) != '0);

  RETRY_ACK_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    retryHandshake);

  PCRD_GRANT_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    rspGrantSend);

  DIRECTORY_EVICTION: cover property (
    @(posedge clk) disable iff (!resetn)
    sfVictimValid);

  ATOMIC_EXECUTED: cover property (
    @(posedge clk) disable iff (!resetn)
    atomicValid);

  SNOOP_ISSUED: cover property (
    @(posedge clk) disable iff (!resetn)
    snpIssueFire);

  EXCLUSIVE_OKAY: cover property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && rspOutReady && (response.respErr == RESP_ERR_EXOK));
endmodule

bind chi_hnf_top chi_proto_sva #(
  .CFG(CFG),
  .POS_DEPTH(POS_DEPTH),
  .POS_W(POS_W)
) chi_hnf_protocol_assertions (
  .clk(clk),
  .resetn(resetn),
  .reqInValid(reqInValid),
  .reqInReady(reqInReady),
  .reqInFlit(reqInFlit),
  .reqOutValid(reqOutValid),
  .reqOutReady(reqOutReady),
  .reqOutFlit(reqOutFlit),
  .rspOutValid(rspOutValid),
  .rspOutReady(rspOutReady),
  .rspOutFlit(rspOutFlit),
  .snpOutValid(snpOutValid),
  .snpOutReady(snpOutReady),
  .snpOutFlit(snpOutFlit),
  .datOutValid(datOutValid),
  .datOutReady(datOutReady),
  .datOutFlit(datOutFlit),
  .retryHandshake(retryHandshake),
  .rspGrantSend(rspGrantSend),
  .rspEntrySend(rspEntrySend),
  .rspEntry(rspEntry),
  .datEntrySend(datEntrySend),
  .datEntry(datEntry),
  .datEntryToPull(datEntryToPull),
  .eSnpDone(eSnpDone),
  .eCompReady(eCompReady),
  .eCompIsData(eCompIsData),
  .eReceiptOwed(eReceiptOwed),
  .eCompOwed(eCompOwed),
  .posActive(posActive),
  .posStarted(posStarted),
  .sfVictimValid(sfVictimValid),
  .atomicValid(atomicValid),
  .snpIssueFire(snpIssueFire)
);
