interface chi_if #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
);
  import chi_pkg::*;

  localparam int unsigned REQ_FLIT_W = reqFlitWidth(CFG);
  localparam int unsigned RSP_FLIT_W = rspFlitWidth(CFG);
  localparam int unsigned SNP_FLIT_W = snpFlitWidth(CFG);
  localparam int unsigned DAT_FLIT_W = datFlitWidth(CFG);
  localparam int unsigned REQ_CHK_W = parityWidth(REQ_FLIT_W);
  localparam int unsigned RSP_CHK_W = parityWidth(RSP_FLIT_W);
  localparam int unsigned SNP_CHK_W = parityWidth(SNP_FLIT_W);
  localparam int unsigned DAT_CHK_W = parityWidth(DAT_FLIT_W);

  logic CLK;
  logic RESETn;

  logic TXLINKACTIVEREQ;
  logic TXLINKACTIVEACK;
  logic RXLINKACTIVEREQ;
  logic RXLINKACTIVEACK;
  logic TXSACTIVE;
  logic RXSACTIVE;
  logic SYSCOREQ;
  logic SYSCOACK;

  logic TXLINKACTIVEREQCHK;
  logic TXLINKACTIVEACKCHK;
  logic RXLINKACTIVEREQCHK;
  logic RXLINKACTIVEACKCHK;
  logic TXSACTIVECHK;
  logic RXSACTIVECHK;
  logic SYSCOREQCHK;
  logic SYSCOACKCHK;

  logic TXREQFLITPEND;
  logic TXREQFLITV;
  logic TXREQLCRDV;
  logic [REQ_FLIT_W-1:0] TXREQFLIT;
  logic TXREQFLITPENDCHK;
  logic TXREQFLITVCHK;
  logic TXREQLCRDVCHK;
  logic [REQ_CHK_W-1:0] TXREQFLITCHK;

  logic RXREQFLITPEND;
  logic RXREQFLITV;
  logic RXREQLCRDV;
  logic [REQ_FLIT_W-1:0] RXREQFLIT;
  logic RXREQFLITPENDCHK;
  logic RXREQFLITVCHK;
  logic RXREQLCRDVCHK;
  logic [REQ_CHK_W-1:0] RXREQFLITCHK;

  logic TXRSPFLITPEND;
  logic TXRSPFLITV;
  logic TXRSPLCRDV;
  logic [RSP_FLIT_W-1:0] TXRSPFLIT;
  logic TXRSPFLITPENDCHK;
  logic TXRSPFLITVCHK;
  logic TXRSPLCRDVCHK;
  logic [RSP_CHK_W-1:0] TXRSPFLITCHK;

  logic RXRSPFLITPEND;
  logic RXRSPFLITV;
  logic RXRSPLCRDV;
  logic [RSP_FLIT_W-1:0] RXRSPFLIT;
  logic RXRSPFLITPENDCHK;
  logic RXRSPFLITVCHK;
  logic RXRSPLCRDVCHK;
  logic [RSP_CHK_W-1:0] RXRSPFLITCHK;

  logic TXSNPFLITPEND;
  logic TXSNPFLITV;
  logic TXSNPLCRDV;
  logic [SNP_FLIT_W-1:0] TXSNPFLIT;
  logic TXSNPFLITPENDCHK;
  logic TXSNPFLITVCHK;
  logic TXSNPLCRDVCHK;
  logic [SNP_CHK_W-1:0] TXSNPFLITCHK;

  logic RXSNPFLITPEND;
  logic RXSNPFLITV;
  logic RXSNPLCRDV;
  logic [SNP_FLIT_W-1:0] RXSNPFLIT;
  logic RXSNPFLITPENDCHK;
  logic RXSNPFLITVCHK;
  logic RXSNPLCRDVCHK;
  logic [SNP_CHK_W-1:0] RXSNPFLITCHK;

  logic TXDATFLITPEND;
  logic TXDATFLITV;
  logic TXDATLCRDV;
  logic [DAT_FLIT_W-1:0] TXDATFLIT;
  logic TXDATFLITPENDCHK;
  logic TXDATFLITVCHK;
  logic TXDATLCRDVCHK;
  logic [DAT_CHK_W-1:0] TXDATFLITCHK;

  logic RXDATFLITPEND;
  logic RXDATFLITV;
  logic RXDATLCRDV;
  logic [DAT_FLIT_W-1:0] RXDATFLIT;
  logic RXDATFLITPENDCHK;
  logic RXDATFLITVCHK;
  logic RXDATLCRDVCHK;
  logic [DAT_CHK_W-1:0] RXDATFLITCHK;
endinterface
