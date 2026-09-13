module chi_mn_sva #(
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
  input logic snpOutValid,
  input logic snpOutReady,
  input chi_pkg::chi_noc_flit_t snpOutFlit,
  input logic rspOutValid,
  input logic rspOutReady,
  input chi_pkg::chi_noc_flit_t rspOutFlit,
  input chi_pkg::chi_req_flit_t activeReq,
  input chi_pkg::chi_rsp_flit_t completion
);
  import chi_pkg::*;

  REQ_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqInValid && !reqInReady
      |=> reqInValid && $stable(reqInFlit));

  RSP_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspInValid && !rspInReady
      |=> rspInValid && $stable(rspInFlit));

  SNP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    snpOutValid && !snpOutReady
      |=> snpOutValid && $stable(snpOutFlit));

  RSP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && !rspOutReady
      |=> rspOutValid && $stable(rspOutFlit));

  DVM_RESPONSE_ID_CONSISTENT: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid
      |-> ((completion.tgtId == activeReq.srcId)
           && (completion.txnId == activeReq.txnId)));

  DVM_COMPLETION: cover property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && rspOutReady
      && (activeReq.opcode == REQ_DVM_OP)
      && (completion.opcode == RSP_COMP));
endmodule

bind chi_mn_dvm chi_mn_sva #(
  .CFG(CFG)
) chi_mn_protocol_assertions (
  .clk(clk),
  .resetn(resetn),
  .reqInValid(reqInValid),
  .reqInReady(reqInReady),
  .reqInFlit(reqInFlit),
  .rspInValid(rspInValid),
  .rspInReady(rspInReady),
  .rspInFlit(rspInFlit),
  .snpOutValid(snpOutValid),
  .snpOutReady(snpOutReady),
  .snpOutFlit(snpOutFlit),
  .rspOutValid(rspOutValid),
  .rspOutReady(rspOutReady),
  .rspOutFlit(rspOutFlit),
  .activeReq(activeReq),
  .completion(completion)
);
