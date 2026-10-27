// One crosspoint (XP) of the unified fabric. Every topology is built from
// this block: a mesh, a ring and a crossbar differ only in how many network
// ports each crosspoint has and in how a wrapper wires them together.
//
// Ports 0 .. NUM_NET_PORTS-1 are network links and the remaining
// NUM_DEV_PORTS ports attach nodes. The four channels have one chi_router
// each and share nothing, so a blocked REQ network can never hold up a
// response, snoop or data flit (IHI 0050H B13.4.1).
//
// The crosspoint routes on the NodeID alone; see chi_route_compute for the
// per-topology route rule.
module chi_xp #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter chi_cfg_pkg::chi_topology_e TOPOLOGY = CFG.topology,
  parameter int unsigned XP_ID = 0,
  parameter int unsigned NUM_XP = chi_pkg::numXpOf(CFG),
  parameter int unsigned NUM_NET_PORTS = 4,
  parameter int unsigned NUM_DEV_PORTS = CFG.numDevPortsPerXp,
  parameter logic [NUM_XP*NUM_DEV_PORTS-1:0] POPULATED = '1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS,
  parameter int unsigned COUNT_W = $clog2(OUT_DEPTH + 1)
) (
  input  logic                                      clk,
  input  logic                                      resetn,
  input  logic [3:0][NUM_PORTS-1:0]                 inValid,
  output logic [3:0][NUM_PORTS-1:0]                 inReady,
  input  chi_pkg::chi_noc_flit_t                    inFlit [3:0][NUM_PORTS-1:0],
  output logic [3:0][NUM_PORTS-1:0]                 outValid,
  input  logic [3:0][NUM_PORTS-1:0]                 outReady,
  output chi_pkg::chi_noc_flit_t                    outFlit [3:0][NUM_PORTS-1:0],
  output logic [3:0][NUM_PORTS-1:0][COUNT_W-1:0]    outCount,
  output logic [3:0]                                routeError
);
  import chi_cfg_pkg::*;

  function automatic chi_cfg_t cfgWithTopology(
    input chi_cfg_t cfg,
    input chi_topology_e topology
  );
    chi_cfg_t value;
    value = cfg;
    value.topology = topology;
    return value;
  endfunction

  // The route rule and the NodeID field layout both follow the topology, so
  // they are evaluated against one configuration that carries it.
  localparam chi_cfg_t XP_CFG = cfgWithTopology(CFG, TOPOLOGY);

  for (genvar channelIndex = 0;
       channelIndex < 4; channelIndex++) begin : channelRouters
    chi_router #(
      .CFG(XP_CFG),
      .XP_ID(XP_ID),
      .NUM_XP(NUM_XP),
      .NUM_NET_PORTS(NUM_NET_PORTS),
      .NUM_DEV_PORTS(NUM_DEV_PORTS),
      .POPULATED(POPULATED),
      .AGE_LIMIT(AGE_LIMIT),
      .OUT_DEPTH(OUT_DEPTH),
      .BUBBLE_FLOW(TOPOLOGY == RING)
    ) router (
      .clk(clk),
      .resetn(resetn),
      .inValid(inValid[channelIndex]),
      .inReady(inReady[channelIndex]),
      .inFlit(inFlit[channelIndex]),
      .outValid(outValid[channelIndex]),
      .outReady(outReady[channelIndex]),
      .outFlit(outFlit[channelIndex]),
      .outCount(outCount[channelIndex]),
      .routeError(routeError[channelIndex])
    );
  end
endmodule
