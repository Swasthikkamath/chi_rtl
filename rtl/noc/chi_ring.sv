// Bidirectional ring of numXp crosspoints. Wiring only: network port 0 of
// every crosspoint is the clockwise ring (out to XP+1, in from XP-1) and
// network port 1 the counter-clockwise ring (out to XP-1, in from XP+1).
//
// Each crosspoint picks the shorter direction with a clockwise tie-break and
// a flit never changes direction, so the two directions are independent rings.
// Each is kept deadlock free by bubble flow control in the crosspoint outputs
// (chi_router, BUBBLE_FLOW): injection needs two free entries on the outgoing
// link and transit needs one, so a ring direction never fills completely and
// a transit flit can always advance unless it is waiting to eject.
module chi_ring #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter int unsigned NUM_XP = CFG.numXp,
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
  output logic                                           routeError,
  // A flit is held in some crosspoint output FIFO.
  output logic                                           busy
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_NET_PORTS = 2;
  localparam int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS;
  localparam int unsigned PORT_CW = 0;
  localparam int unsigned PORT_CCW = 1;

  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInReady;
  chi_noc_flit_t xpInFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutReady;
  chi_noc_flit_t xpOutFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0][COUNT_W-1:0] xpOutCount;
  logic [NUM_XP-1:0][3:0] xpRouteError;

  function automatic int unsigned nextXp(input int unsigned xp);
    return (xp == (NUM_XP - 1)) ? 0 : (xp + 1);
  endfunction

  function automatic int unsigned previousXp(input int unsigned xp);
    return (xp == 0) ? (NUM_XP - 1) : (xp - 1);
  endfunction

  always_comb begin
    for (int unsigned xp = 0; xp < NUM_XP; xp++) begin
      for (int unsigned channel = 0; channel < 4; channel++) begin
        xpInValid[xp][channel][PORT_CW] =
          xpOutValid[previousXp(xp)][channel][PORT_CW];
        xpInFlit[xp][channel][PORT_CW] =
          xpOutFlit[previousXp(xp)][channel][PORT_CW];
        xpInValid[xp][channel][PORT_CCW] =
          xpOutValid[nextXp(xp)][channel][PORT_CCW];
        xpInFlit[xp][channel][PORT_CCW] =
          xpOutFlit[nextXp(xp)][channel][PORT_CCW];
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
        xpOutReady[xp][channel][PORT_CW] =
          xpInReady[nextXp(xp)][channel][PORT_CW];
        xpOutReady[xp][channel][PORT_CCW] =
          xpInReady[previousXp(xp)][channel][PORT_CCW];
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
  assign busy = xpOutCount != '0;

  for (genvar xpIndex = 0; xpIndex < NUM_XP; xpIndex++) begin : xps
    chi_xp #(
      .CFG(CFG),
      .TOPOLOGY(RING),
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
