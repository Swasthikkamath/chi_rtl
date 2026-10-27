module chi_hnf_compile (
  input logic clk,
  input logic resetn
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_RNF =
    (CHI_CFG_DEFAULT.numRnf > 0) ? CHI_CFG_DEFAULT.numRnf : 1;
  localparam logic [CHI_MAX_NODEID_W-1:0] HN_NODE_ID =
    encodeNodeId(CHI_CFG_DEFAULT, 0, 0, 0, 0);
  localparam logic [CHI_MAX_NODEID_W-1:0] SN_NODE_ID =
    encodeNodeId(CHI_CFG_DEFAULT, 1, 0, 0, 0);
  localparam logic [CHI_MAX_NODEID_W-1:0] RNF_NODE_IDS [NUM_RNF] = '{
    encodeNodeId(CHI_CFG_DEFAULT, 0, 0, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 1, 0, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 1, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 1, 1, 0)
  };

  logic reqInReady;
  logic rspInReady;
  logic datInReady;
  logic reqOutValid;
  logic rspOutValid;
  logic snpOutValid;
  logic datOutValid;
  logic hnfIdle;
  chi_noc_flit_t reqOutFlit;
  chi_noc_flit_t rspOutFlit;
  chi_noc_flit_t snpOutFlit;
  chi_noc_flit_t datOutFlit;

  chi_hnf_top #(
    .CFG(CHI_CFG_DEFAULT), .HN_NODE_ID(HN_NODE_ID),
    .SN_NODE_ID(SN_NODE_ID), .NUM_RNF(NUM_RNF),
    .RNF_NODE_IDS(RNF_NODE_IDS)
  ) hnf (
    .clk, .resetn, .policy(CHI_HNF_POLICY_DEFAULT),
    .reqInValid(1'b0), .reqInReady, .reqInFlit('0),
    .rspInValid(1'b0), .rspInReady, .rspInFlit('0),
    .datInValid(1'b0), .datInReady, .datInFlit('0),
    .reqOutValid, .reqOutReady(1'b1), .reqOutFlit,
    .rspOutValid, .rspOutReady(1'b1), .rspOutFlit,
    .snpOutValid, .snpOutReady(1'b1), .snpOutFlit,
    .datOutValid, .datOutReady(1'b1), .datOutFlit,
    .idle(hnfIdle)
  );

  generate
    begin : chi_cfg_check
      initial begin
        if (CHI_CFG_DEFAULT.posEntries == 0)
          $fatal(1, "HN-F requires at least one POS entry");
        if ((CHI_CFG_DEFAULT.snpFilterEntries == 0)
            || (CHI_CFG_DEFAULT.snpFilterWays == 0)
            || ((CHI_CFG_DEFAULT.snpFilterEntries
                 % CHI_CFG_DEFAULT.snpFilterWays) != 0))
          $fatal(1, "HN-F snoop filter geometry is invalid");
        if (CHI_CFG_DEFAULT.snpFilterWays
            > CHI_CFG_DEFAULT.snpFilterEntries)
          $fatal(1, "HN-F snoop filter has more ways than entries");
      end
    end
  endgenerate
endmodule
