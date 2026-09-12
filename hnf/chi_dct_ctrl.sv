module chi_dct_ctrl #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input  chi_pkg::chi_req_opcode_e requestOpcode,
  input  chi_pkg::chi_order_e requestOrder,
  input  logic [CFG.nodeIdW-1:0] requester,
  input  logic [CFG.txnIdW-1:0] requesterTxnId,
  input  logic forwarderKnown,
  input  logic [CFG.nodeIdW-1:0] forwarder,
  input  logic forwarderClean,
  input  logic dataPresent,
  input  logic dataFullLine,
  input  logic dataPoison,
  input  logic dataError,
  input  logic responseCompatible,
  input  logic mteCompatible,
  output logic eligible,
  output logic fallbackToHome,
  output chi_pkg::chi_snp_opcode_e snoopOpcode,
  output logic [CFG.nodeIdW-1:0] fwdNid,
  output logic [CFG.txnIdW-1:0] fwdTxnId,
  output logic retToSrc
);
  import chi_pkg::*;

  logic coherentRead;

  always_comb begin
    coherentRead = (requestOpcode == REQ_READ_SHARED)
                   || (requestOpcode == REQ_READ_CLEAN)
                   || (requestOpcode == REQ_READ_UNIQUE)
                   || (requestOpcode == REQ_READ_NOT_SHARED_DIRTY)
                   || (requestOpcode == REQ_READ_PREFER_UNIQUE);
    eligible = CFG.dctEn && coherentRead && forwarderKnown
               && forwarderClean && dataPresent && dataFullLine
               && !dataPoison && !dataError && responseCompatible
               && (requestOrder != ORDER_ENDPOINT)
               && (!CFG.mteEn || mteCompatible);
    fwdNid = requester;
    fwdTxnId = requesterTxnId;
    retToSrc = !eligible;
    case (requestOpcode)
      REQ_READ_SHARED: snoopOpcode = eligible ? SNP_SHARED_FWD : SNP_SHARED;
      REQ_READ_CLEAN: snoopOpcode = eligible ? SNP_CLEAN_FWD : SNP_CLEAN;
      REQ_READ_UNIQUE: snoopOpcode = eligible ? SNP_UNIQUE_FWD : SNP_UNIQUE;
      REQ_READ_NOT_SHARED_DIRTY:
        snoopOpcode = eligible ? SNP_NOT_SHARED_DIRTY_FWD : SNP_NOT_SHARED_DIRTY;
      REQ_READ_PREFER_UNIQUE:
        snoopOpcode = eligible ? SNP_PREFER_UNIQUE_FWD : SNP_PREFER_UNIQUE;
      default: snoopOpcode = SNP_SHARED;
    endcase
    if (forwarder == requester)
      eligible = 1'b0;
    fallbackToHome = coherentRead && !eligible;
  end
endmodule
