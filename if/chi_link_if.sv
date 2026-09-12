interface chi_link_if #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
);
  import chi_pkg::*;
  localparam int unsigned REQ_FLIT_W = reqFlitWidth(CFG);
  localparam int unsigned RSP_FLIT_W = rspFlitWidth(CFG);
  localparam int unsigned SNP_FLIT_W = snpFlitWidth(CFG);
  localparam int unsigned DAT_FLIT_W = datFlitWidth(CFG);

  logic reqTxValid, reqTxPending, reqTxCreditValid;
  logic [REQ_FLIT_W-1:0] reqTxFlit;
  logic rspTxValid, rspTxPending, rspTxCreditValid;
  logic [RSP_FLIT_W-1:0] rspTxFlit;
  logic snpTxValid, snpTxPending, snpTxCreditValid;
  logic [SNP_FLIT_W-1:0] snpTxFlit;
  logic datTxValid, datTxPending, datTxCreditValid;
  logic [DAT_FLIT_W-1:0] datTxFlit;

  logic reqRxValid, reqRxPending, reqRxCreditValid;
  logic [REQ_FLIT_W-1:0] reqRxFlit;
  logic rspRxValid, rspRxPending, rspRxCreditValid;
  logic [RSP_FLIT_W-1:0] rspRxFlit;
  logic snpRxValid, snpRxPending, snpRxCreditValid;
  logic [SNP_FLIT_W-1:0] snpRxFlit;
  logic datRxValid, datRxPending, datRxCreditValid;
  logic [DAT_FLIT_W-1:0] datRxFlit;

  chi_req_flit_t reqTxFields, reqRxFields;
  chi_rsp_flit_t rspTxFields, rspRxFields;
  chi_snp_flit_t snpTxFields, snpRxFields;
  chi_dat_flit_t datTxFields, datRxFields;
endinterface
