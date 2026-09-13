module chi_sva_compile (
  input logic clk,
  input logic resetn
);
  chi_link_compile link_compile (
    .clk(clk),
    .resetn(resetn)
  );

  chi_hnf_compile hnf_compile (
    .clk(clk),
    .resetn(resetn)
  );

  logic mnReqReady;
  logic mnRspReady;
  logic mnSnpValid;
  logic mnRspValid;
  logic mnIdle;
  chi_pkg::chi_noc_flit_t mnSnpFlit;
  chi_pkg::chi_noc_flit_t mnRspFlit;

  chi_mn_dvm mn_compile (
    .clk(clk),
    .resetn(resetn),
    .reqInValid(1'b0),
    .reqInReady(mnReqReady),
    .reqInFlit('0),
    .rspInValid(1'b0),
    .rspInReady(mnRspReady),
    .rspInFlit('0),
    .snpOutValid(mnSnpValid),
    .snpOutReady(1'b1),
    .snpOutFlit(mnSnpFlit),
    .rspOutValid(mnRspValid),
    .rspOutReady(1'b1),
    .rspOutFlit(mnRspFlit),
    .idle(mnIdle)
  );
endmodule
