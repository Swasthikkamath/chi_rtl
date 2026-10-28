// REQ injection regulator of the Request Node ports.
//
// Each port has its own token bucket: qosRegRate tokens are added every 256
// cycles, up to qosRegBurst, and a REQ flit enters the fabric only by taking
// a token. A port with no token holds its REQ in the link receiver, which
// back-pressures the Requester through L-Credits; holding a request never
// blocks a response, so the regulator cannot deadlock the fabric. A port
// starts with a full bucket. With qosRegEn 0 every flit passes.
//
// Valid towards the fabric depends only on the incoming valid and the
// bucket, never on the fabric's ready.
module chi_qos_reg #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_PORTS-1:0] inValid,
  output logic [NUM_PORTS-1:0] inReady,
  output logic [NUM_PORTS-1:0] outValid,
  input  logic [NUM_PORTS-1:0] outReady,
  // For the bound assertions and the counters.
  output logic [NUM_PORTS-1:0][7:0] tokens
);
  localparam logic [8:0] RATE = (CFG.qosRegRate > 256) ? 9'd256 : 9'(CFG.qosRegRate);
  localparam logic [7:0] BURST = (CFG.qosRegBurst > 255) ? 8'd255
                                 : ((CFG.qosRegBurst == 0) ? 8'd1 : 8'(CFG.qosRegBurst));

  logic [NUM_PORTS-1:0][7:0] fraction;  // 1/256 tokens
  logic [NUM_PORTS-1:0] allow;

  always_comb
    for (int unsigned p = 0; p < NUM_PORTS; p++)
      allow[p] = !CFG.qosRegEn || (tokens[p] != 8'd0);

  // Forward.
  always_comb
    for (int unsigned p = 0; p < NUM_PORTS; p++)
      outValid[p] = inValid[p] && allow[p];

  // Backward.
  always_comb
    for (int unsigned p = 0; p < NUM_PORTS; p++)
      inReady[p] = outReady[p] && allow[p];

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned p = 0; p < NUM_PORTS; p++) begin
        tokens[p] <= BURST;
        fraction[p] <= '0;
      end
    end else if (CFG.qosRegEn) begin
      for (int unsigned p = 0; p < NUM_PORTS; p++) begin
        logic [8:0] sum;
        logic [8:0] level;
        sum = {1'b0, fraction[p]} + RATE;
        level = {1'b0, tokens[p]} + {8'd0, sum[8]}
                - {8'd0, (outValid[p] && outReady[p])};
        fraction[p] <= sum[7:0];
        tokens[p] <= (level > {1'b0, BURST}) ? BURST : level[7:0];
      end
    end
  end
endmodule
