// Direct Write Transfer decision for the Home Node. With DoDWT set the
// Subordinate returns DBIDResp directly to the Requester, receives the write
// data from it, and returns Comp to the Home, which then completes the
// transaction upstream (IHI 0050H B2.3.2.1, B13.10.24).
module chi_dwt_ctrl #(
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
  input  logic tagOperation,
  output logic eligible,
  output logic doDwt,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] returnNid,
  output logic [chi_cfg_pkg::CHI_TXNID_FLIT_W-1:0] returnTxnId
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  logic writeNoSnpFamily;
  logic orderPermitted;

  always_comb begin
    // Only the immediate non-snoopable writes can be forwarded whole; a
    // CopyBack write already carries its data from the Requester to the Home.
    writeNoSnpFamily = (requestOpcode == REQ_WRITE_NO_SNP_FULL)
                       || (requestOpcode == REQ_WRITE_NO_SNP_PTL)
                       || (requestOpcode == REQ_WRITE_NO_SNP_DEF);
    orderPermitted = (requestOrder == ORDER_NONE)
                     || (requestOrder == ORDER_REQUEST_ACCEPTED);

    // Tag maintenance is kept at the Home so the TagMatch response does not
    // have to be produced by the Subordinate.
    eligible = CFG.dwtEn && writeNoSnpFamily && orderPermitted
               && !snoopRequired && !errorDetected && !exclusiveAccess
               && !atomicAccess && !tagOperation;
    doDwt = eligible;
    returnNid = eligible ? requester : '0;
    returnTxnId = eligible ? requesterTxnId : '0;
  end
endmodule
