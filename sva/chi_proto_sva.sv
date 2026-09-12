module chi_proto_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input logic clk,
  input logic resetn,
  input logic reqInValid,
  input logic reqInReady,
  input chi_pkg::chi_noc_flit_t reqInFlit,
  input logic rspInValid,
  input logic rspInReady,
  input chi_pkg::chi_noc_flit_t rspInFlit,
  input logic datInValid,
  input logic datInReady,
  input chi_pkg::chi_noc_flit_t datInFlit,
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
  input chi_pkg::chi_req_flit_t incomingReq,
  input chi_pkg::chi_rsp_flit_t incomingRsp,
  input chi_pkg::chi_dat_flit_t incomingDat,
  input chi_pkg::chi_req_flit_t activeReq,
  input chi_pkg::chi_rsp_flit_t responseFlit,
  input logic retryAckSend,
  input logic retryAck,
  input logic [3:0] retryClass,
  input logic retryGrantValid,
  input logic retryGrantSend,
  input logic [3:0] retryGrantClass,
  input chi_pkg::chi_rsp_flit_t grantFlit,
  input logic dctEligible,
  input logic sfBackInvDone,
  input logic activeExclOkay,
  input logic activeWrite
);
  import chi_pkg::*;

  function automatic logic isRead(input chi_req_opcode_e opcode);
    return opcode inside {
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_ONCE, REQ_READ_NO_SNP,
      REQ_READ_UNIQUE, REQ_READ_NO_SNP_SEP,
      REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID,
      REQ_READ_NOT_SHARED_DIRTY, REQ_READ_PREFER_UNIQUE
    };
  endfunction

  REQ_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqInValid && !reqInReady
      |=> reqInValid && $stable(reqInFlit));

  RSP_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspInValid && !rspInReady
      |=> rspInValid && $stable(rspInFlit));

  DAT_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    datInValid && !datInReady
      |=> datInValid && $stable(datInFlit));

  function automatic logic isWrite(input chi_req_opcode_e opcode);
    return opcode inside {
      REQ_WRITE_EVICT_FULL, REQ_WRITE_CLEAN_FULL,
      REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_FULL,
      REQ_WRITE_BACK_PTL, REQ_WRITE_BACK_FULL,
      REQ_WRITE_NO_SNP_PTL, REQ_WRITE_NO_SNP_FULL,
      REQ_WRITE_UNIQUE_ZERO, REQ_WRITE_NO_SNP_ZERO
    };
  endfunction

  REQ_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && !reqOutReady
      |=> reqOutValid && $stable(reqOutFlit));

  RSP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && !rspOutReady
      |=> rspOutValid && $stable(rspOutFlit));

  SNP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    snpOutValid && !snpOutReady
      |=> snpOutValid && $stable(snpOutFlit));

  DAT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    datOutValid && !datOutReady
      |=> datOutValid && $stable(datOutFlit));

  ACTIVE_RESPONSE_ID_CONSISTENT: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && !retryAckSend && !retryGrantSend
      |-> ((responseFlit.tgtId == activeReq.srcId)
           && (responseFlit.txnId == activeReq.txnId)));

  RETRY_RESPONSE_ID_CONSISTENT: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && retryAckSend
      |-> ((responseFlit.tgtId == incomingReq.srcId)
           && (responseFlit.txnId == incomingReq.txnId)
           && (responseFlit.opcode == RSP_RETRY_ACK)));

  ONE_COMPLETION_PATH: assert property (
    @(posedge clk) disable iff (!resetn)
    !((rspInValid && rspInReady
       && (incomingRsp.opcode inside {
         RSP_COMP, RSP_COMP_DBID_RESP, RSP_COMP_CMO, RSP_COMP_PERSIST
       }))
      && (datInValid && datInReady
          && (incomingDat.opcode == DAT_COMP_DATA)
          && (incomingDat.dataId == incomingDat.numDat))));

  // PCrdGrant must not carry a TxnID or a DBID (IHI 0050H B2.5.5).
  PCRD_GRANT_FIELDS_UNUSED: assert property (
    @(posedge clk) disable iff (!resetn)
    retryGrantSend
      |-> ((grantFlit.opcode == RSP_PCRD_GRANT)
           && (grantFlit.txnId == '0)
           && (grantFlit.dbIdOrGroupId == '0)));

  // A RetryAck and a PCrdGrant must never contend for the response channel.
  RETRY_ACK_GRANT_MUTUALLY_EXCLUSIVE: assert property (
    @(posedge clk) disable iff (!resetn)
    !(retryAckSend && retryGrantSend));

  RETRY_ACK_THEN_PCRD_GRANT_CLASS: cover property (
    @(posedge clk) disable iff (!resetn)
    retryGrantValid && $past(retryAck)
      && (retryGrantClass == $past(retryClass)));

  PCRD_GRANT_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    retryGrantSend && rspOutReady);

  DCT_SNOOP_FORWARD_PATH: cover property (
    @(posedge clk) disable iff (!resetn)
    dctEligible && snpOutValid && snpOutReady);

  DIRECTORY_BACK_INVALIDATION: cover property (
    @(posedge clk) disable iff (!resetn)
    sfBackInvDone);

  EXCLUSIVE_SUCCESS: cover property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && rspOutReady && activeReq.exclOrSnoopMeOrCah
      && activeExclOkay);

  BASIC_READ_FLOW: cover property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && rspOutReady && isRead(activeReq.opcode));

  BASIC_WRITE_FLOW: cover property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && rspOutReady && activeWrite
      && isWrite(activeReq.opcode));
endmodule

bind chi_hnf_top chi_proto_sva #(
  .CFG(CFG)
) chi_hnf_protocol_assertions (
  .clk(clk),
  .resetn(resetn),
  .reqInValid(reqInValid),
  .reqInReady(reqInReady),
  .reqInFlit(reqInFlit),
  .rspInValid(rspInValid),
  .rspInReady(rspInReady),
  .rspInFlit(rspInFlit),
  .datInValid(datInValid),
  .datInReady(datInReady),
  .datInFlit(datInFlit),
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
  .incomingReq(incomingReq),
  .incomingRsp(incomingRsp),
  .incomingDat(incomingDat),
  .activeReq(activeReq),
  .responseFlit(responseFlit),
  .retryAckSend(retryAckSend),
  .retryAck(retryAck),
  .retryClass(retryClass),
  .retryGrantValid(retryGrantValid),
  .retryGrantSend(retryGrantSend),
  .retryGrantClass(retryGrantClass),
  .grantFlit(grantFlit),
  .dctEligible(dctEligible),
  .sfBackInvDone(sfBackInvDone),
  .activeExclOkay(activeExclOkay),
  .activeWrite(activeWrite)
);
