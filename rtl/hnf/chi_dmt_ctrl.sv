// Direct Memory Transfer decision for the Home Node. With DMT the Home names
// the Requester in the downstream read so the Subordinate returns CompData
// straight to it, and for the separate-response flow the Home sends
// RespSepData while the Subordinate sends DataSepResp (IHI 0050H B2.5.1.1,
// B2.5.1.2).
module chi_dmt_ctrl #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input  chi_pkg::chi_req_opcode_e requestOpcode,
  input  chi_pkg::chi_order_e requestOrder,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requester,
  input  logic [chi_cfg_pkg::CHI_TXNID_FLIT_W-1:0] requesterTxnId,
  input  logic snoopRequired,
  input  logic errorDetected,
  input  logic exclusiveAccess,
  input  logic atomicAccess,
  output logic eligible,
  output logic separateResponse,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] returnNid,
  output logic [chi_cfg_pkg::CHI_TXNID_FLIT_W-1:0] returnTxnId
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  logic readNoSnpFamily;
  logic orderPermitted;

  always_comb begin
    readNoSnpFamily = (requestOpcode == REQ_READ_NO_SNP)
                      || (requestOpcode == REQ_READ_NO_SNP_SEP);
    separateResponse = requestOpcode == REQ_READ_NO_SNP_SEP;

    // Endpoint ordering needs the Home in the completion path, so DMT is
    // restricted to the unordered and request-accepted cases here. That
    // restriction is an implementation choice, not a protocol rule.
    orderPermitted = (requestOrder == ORDER_NONE)
                     || (requestOrder == ORDER_REQUEST_ACCEPTED);

    // A request must not use DMT when the interconnect has detected an error,
    // and atomics may not use DMT at all. Exclusives are excluded locally so
    // the exclusive monitor still observes the data.
    eligible = CFG.dmtEn && readNoSnpFamily && orderPermitted
               && !snoopRequired && !errorDetected && !exclusiveAccess
               && !atomicAccess;

    returnNid = eligible ? requester : '0;
    returnTxnId = eligible ? requesterTxnId : '0;
  end
endmodule
