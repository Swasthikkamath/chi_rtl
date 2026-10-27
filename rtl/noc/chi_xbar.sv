// Crossbar of numXp fully connected crosspoints. Wiring only: crosspoint a
// has numXp-1 network ports, and its port p is the direct link to crosspoint
// p when p < a, to crosspoint p+1 otherwise. Every route is at most one
// network hop, so there is no transit traffic and a flit waiting to eject can
// only hold back flits bound for the same crosspoint.
//
// With numXp == 1 there are no network ports and every node is a device port
// of a single crosspoint, which is the central crossbar the design used before
// the fabric was unified, now with registered outputs.
module chi_xbar #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter int unsigned NUM_XP = (CFG.numXp > 0) ? CFG.numXp : 1,
  parameter int unsigned NUM_DEV_PORTS = CFG.numDevPortsPerXp,
  parameter logic [NUM_XP*NUM_DEV_PORTS-1:0] POPULATED = '1,
  parameter int unsigned COUNT_W = $clog2(OUT_DEPTH + 1)
) (
  input  logic                                           clk,
  input  logic                                           resetn,
  input  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0]      devInValid,
  output logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0]      devInReady,
  input  chi_pkg::chi_noc_flit_t                         devInFlit [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0],
  output logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0]      devOutValid,
  input  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0]      devOutReady,
  output chi_pkg::chi_noc_flit_t                         devOutFlit [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0],
  output logic                                           routeError
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_NET_PORTS = (NUM_XP > 1) ? (NUM_XP - 1) : 0;
  localparam int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS;

  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInReady;
  chi_noc_flit_t xpInFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutReady;
  chi_noc_flit_t xpOutFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0][COUNT_W-1:0] xpOutCount;
  logic [NUM_XP-1:0][3:0] xpRouteError;

  // The crosspoint at the far end of network port p of crosspoint xp.
  function automatic int unsigned peerXp(
    input int unsigned xp,
    input int unsigned port
  );
    return (port < xp) ? port : (port + 1);
  endfunction

  // The network port of crosspoint xp that leads to crosspoint peer.
  function automatic int unsigned portToward(
    input int unsigned xp,
    input int unsigned peer
  );
    return (peer < xp) ? peer : (peer - 1);
  endfunction

  always_comb begin
    for (int unsigned xp = 0; xp < NUM_XP; xp++) begin
      for (int unsigned channel = 0; channel < 4; channel++) begin
        for (int unsigned port = 0; port < NUM_NET_PORTS; port++) begin
          xpInValid[xp][channel][port] =
            xpOutValid[peerXp(xp, port)][channel][portToward(peerXp(xp, port), xp)];
          xpInFlit[xp][channel][port] =
            xpOutFlit[peerXp(xp, port)][channel][portToward(peerXp(xp, port), xp)];
        end
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++) begin
          xpInValid[xp][channel][NUM_NET_PORTS + device] =
            devInValid[xp][channel][device];
          xpInFlit[xp][channel][NUM_NET_PORTS + device] =
            devInFlit[xp][channel][device];
        end
      end
    end
  end

  always_comb begin
    for (int unsigned xp = 0; xp < NUM_XP; xp++)
      for (int unsigned channel = 0; channel < 4; channel++)
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++) begin
          devOutValid[xp][channel][device] =
            xpOutValid[xp][channel][NUM_NET_PORTS + device];
          devOutFlit[xp][channel][device] =
            xpOutFlit[xp][channel][NUM_NET_PORTS + device];
        end
  end

  always_comb begin
    for (int unsigned xp = 0; xp < NUM_XP; xp++) begin
      for (int unsigned channel = 0; channel < 4; channel++) begin
        for (int unsigned port = 0; port < NUM_NET_PORTS; port++)
          xpOutReady[xp][channel][port] =
            xpInReady[peerXp(xp, port)][channel][portToward(peerXp(xp, port), xp)];
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++)
          xpOutReady[xp][channel][NUM_NET_PORTS + device] =
            devOutReady[xp][channel][device];
      end
    end
  end

  always_comb begin
    for (int unsigned xp = 0; xp < NUM_XP; xp++)
      for (int unsigned channel = 0; channel < 4; channel++)
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++)
          devInReady[xp][channel][device] =
            xpInReady[xp][channel][NUM_NET_PORTS + device];
  end

  assign routeError = |xpRouteError;

  for (genvar xpIndex = 0; xpIndex < NUM_XP; xpIndex++) begin : xps
    chi_xp #(
      .CFG(CFG),
      .TOPOLOGY(CROSSBAR),
      .XP_ID(xpIndex),
      .NUM_XP(NUM_XP),
      .NUM_NET_PORTS(NUM_NET_PORTS),
      .NUM_DEV_PORTS(NUM_DEV_PORTS),
      .POPULATED(POPULATED),
      .AGE_LIMIT(AGE_LIMIT),
      .OUT_DEPTH(OUT_DEPTH)
    ) xp (
      .clk(clk),
      .resetn(resetn),
      .inValid(xpInValid[xpIndex]),
      .inReady(xpInReady[xpIndex]),
      .inFlit(xpInFlit[xpIndex]),
      .outValid(xpOutValid[xpIndex]),
      .outReady(xpOutReady[xpIndex]),
      .outFlit(xpOutFlit[xpIndex]),
      .outCount(xpOutCount[xpIndex]),
      .routeError(xpRouteError[xpIndex])
    );
  end
endmodule
