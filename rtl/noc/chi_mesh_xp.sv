module chi_mesh_xp #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned CURRENT_X = 0,
  parameter int unsigned CURRENT_Y = 0,
  parameter int unsigned NUM_VALID_NODES = 1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    VALID_NODE_IDS [NUM_VALID_NODES-1:0] = '{default: '0},
  parameter int unsigned NUM_PORTS = 4 + CFG.numDevPortsPerXp
) (
  input  logic                                      clk,
  input  logic                                      resetn,
  input  logic [3:0][NUM_PORTS-1:0]                 inValid,
  output logic [3:0][NUM_PORTS-1:0]                 inReady,
  input  chi_pkg::chi_noc_flit_t                    inFlit [3:0][NUM_PORTS-1:0],
  output logic [3:0][NUM_PORTS-1:0]                 outValid,
  input  logic [3:0][NUM_PORTS-1:0]                 outReady,
  output chi_pkg::chi_noc_flit_t                    outFlit [3:0][NUM_PORTS-1:0]
);
  for (genvar channelIndex = 0;
       channelIndex < 4; channelIndex++) begin : channelRouters
    chi_router #(
      .CFG(CFG),
      .CURRENT_X(CURRENT_X),
      .CURRENT_Y(CURRENT_Y),
      .NUM_VALID_NODES(NUM_VALID_NODES),
      .AGE_LIMIT(AGE_LIMIT),
      .VALID_NODE_IDS(VALID_NODE_IDS)
    ) router (
      .clk(clk),
      .resetn(resetn),
      .inValid(inValid[channelIndex]),
      .inReady(inReady[channelIndex]),
      .inFlit(inFlit[channelIndex]),
      .outValid(outValid[channelIndex]),
      .outReady(outReady[channelIndex]),
      .outFlit(outFlit[channelIndex])
    );
  end
endmodule
