module chi_xbar_compile (
  input logic clk,
  input logic resetn
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_INPUTS = 4;
  localparam int unsigned NUM_OUTPUTS = 4;
  localparam logic [CHI_MAX_NODEID_W-1:0]
    OUTPUT_NODE_IDS [NUM_OUTPUTS-1:0] = '{
      CHI_MAX_NODEID_W'(3),
      CHI_MAX_NODEID_W'(2),
      CHI_MAX_NODEID_W'(1),
      CHI_MAX_NODEID_W'(0)
    };

  logic [NUM_INPUTS-1:0] reqInValid;
  logic [NUM_INPUTS-1:0] reqInReady;
  chi_noc_flit_t reqInFlit [NUM_INPUTS-1:0];
  logic [NUM_OUTPUTS-1:0] reqOutValid;
  logic [NUM_OUTPUTS-1:0] reqOutReady;
  chi_noc_flit_t reqOutFlit [NUM_OUTPUTS-1:0];

  logic [NUM_INPUTS-1:0] rspInValid;
  logic [NUM_INPUTS-1:0] rspInReady;
  chi_noc_flit_t rspInFlit [NUM_INPUTS-1:0];
  logic [NUM_OUTPUTS-1:0] rspOutValid;
  logic [NUM_OUTPUTS-1:0] rspOutReady;
  chi_noc_flit_t rspOutFlit [NUM_OUTPUTS-1:0];

  logic [NUM_INPUTS-1:0] snpInValid;
  logic [NUM_INPUTS-1:0] snpInReady;
  chi_noc_flit_t snpInFlit [NUM_INPUTS-1:0];
  logic [NUM_OUTPUTS-1:0] snpOutValid;
  logic [NUM_OUTPUTS-1:0] snpOutReady;
  chi_noc_flit_t snpOutFlit [NUM_OUTPUTS-1:0];

  logic [NUM_INPUTS-1:0] datInValid;
  logic [NUM_INPUTS-1:0] datInReady;
  chi_noc_flit_t datInFlit [NUM_INPUTS-1:0];
  logic [NUM_OUTPUTS-1:0] datOutValid;
  logic [NUM_OUTPUTS-1:0] datOutReady;
  chi_noc_flit_t datOutFlit [NUM_OUTPUTS-1:0];

  always_comb begin
    reqInValid = '0;
    rspInValid = '0;
    snpInValid = '0;
    datInValid = '0;
    reqOutReady = '0;
    rspOutReady = '0;
    snpOutReady = '0;
    datOutReady = '0;
    for (int unsigned inputIndex = 0;
         inputIndex < NUM_INPUTS; inputIndex++) begin
      reqInFlit[inputIndex] = '0;
      rspInFlit[inputIndex] = '0;
      snpInFlit[inputIndex] = '0;
      datInFlit[inputIndex] = '0;
    end
  end

  chi_xbar #(
    .NUM_INPUTS(NUM_INPUTS),
    .NUM_OUTPUTS(NUM_OUTPUTS),
    .AGE_LIMIT(16),
    .OUTPUT_NODE_IDS(OUTPUT_NODE_IDS)
  ) xbar (
    .clk(clk),
    .resetn(resetn),
    .reqInValid(reqInValid),
    .reqInReady(reqInReady),
    .reqInFlit(reqInFlit),
    .reqOutValid(reqOutValid),
    .reqOutReady(reqOutReady),
    .reqOutFlit(reqOutFlit),
    .rspInValid(rspInValid),
    .rspInReady(rspInReady),
    .rspInFlit(rspInFlit),
    .rspOutValid(rspOutValid),
    .rspOutReady(rspOutReady),
    .rspOutFlit(rspOutFlit),
    .snpInValid(snpInValid),
    .snpInReady(snpInReady),
    .snpInFlit(snpInFlit),
    .snpOutValid(snpOutValid),
    .snpOutReady(snpOutReady),
    .snpOutFlit(snpOutFlit),
    .datInValid(datInValid),
    .datInReady(datInReady),
    .datInFlit(datInFlit),
    .datOutValid(datOutValid),
    .datOutReady(datOutReady),
    .datOutFlit(datOutFlit)
  );
endmodule
