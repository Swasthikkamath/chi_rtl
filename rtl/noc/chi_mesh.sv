// meshX by meshY grid of crosspoints. Wiring only: each crosspoint's
// network ports 0..3 (north, south, east, west) connect to its neighbours,
// network ports on the mesh boundary are left unconnected, and every device
// port is brought out to chi_noc_top. Routing is dimension-ordered XY inside
// each crosspoint (chi_route_compute), which never selects a boundary port.
module chi_mesh #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter int unsigned NUM_XP = CFG.meshX * CFG.meshY,
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

  localparam int unsigned NUM_NET_PORTS = 4;
  localparam int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS;
  localparam int unsigned PORT_NORTH = 0;
  localparam int unsigned PORT_SOUTH = 1;
  localparam int unsigned PORT_EAST = 2;
  localparam int unsigned PORT_WEST = 3;

  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpInReady;
  chi_noc_flit_t xpInFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutValid;
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0] xpOutReady;
  chi_noc_flit_t xpOutFlit [NUM_XP-1:0][3:0][NUM_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0][COUNT_W-1:0] xpOutCount;
  logic [NUM_XP-1:0][3:0] xpRouteError;

  // The wiring is split into four blocks, one per direction and side. A block
  // that wrote both a valid and a ready would make every signal it drives
  // appear to depend on every signal it reads, which a linter reports as a
  // combinational loop even though none closes.
  always_comb begin
    xpInValid = '0;
    for (int unsigned xp = 0; xp < NUM_XP; xp++)
      for (int unsigned channel = 0; channel < 4; channel++)
        for (int unsigned port = 0; port < NUM_PORTS; port++)
          xpInFlit[xp][channel][port] = '0;

    for (int unsigned y = 0; y < CFG.meshY; y++) begin
      for (int unsigned x = 0; x < CFG.meshX; x++) begin
        int unsigned xp;
        xp = y * CFG.meshX + x;
        for (int unsigned channel = 0; channel < 4; channel++) begin
          if ((y + 1) < CFG.meshY) begin
            xpInValid[xp][channel][PORT_NORTH] =
              xpOutValid[xp + CFG.meshX][channel][PORT_SOUTH];
            xpInFlit[xp][channel][PORT_NORTH] =
              xpOutFlit[xp + CFG.meshX][channel][PORT_SOUTH];
          end
          if (y > 0) begin
            xpInValid[xp][channel][PORT_SOUTH] =
              xpOutValid[xp - CFG.meshX][channel][PORT_NORTH];
            xpInFlit[xp][channel][PORT_SOUTH] =
              xpOutFlit[xp - CFG.meshX][channel][PORT_NORTH];
          end
          if ((x + 1) < CFG.meshX) begin
            xpInValid[xp][channel][PORT_EAST] =
              xpOutValid[xp + 1][channel][PORT_WEST];
            xpInFlit[xp][channel][PORT_EAST] =
              xpOutFlit[xp + 1][channel][PORT_WEST];
          end
          if (x > 0) begin
            xpInValid[xp][channel][PORT_WEST] =
              xpOutValid[xp - 1][channel][PORT_EAST];
            xpInFlit[xp][channel][PORT_WEST] =
              xpOutFlit[xp - 1][channel][PORT_EAST];
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
    xpOutReady = '0;
    for (int unsigned y = 0; y < CFG.meshY; y++) begin
      for (int unsigned x = 0; x < CFG.meshX; x++) begin
        int unsigned xp;
        xp = y * CFG.meshX + x;
        for (int unsigned channel = 0; channel < 4; channel++) begin
          if ((y + 1) < CFG.meshY)
            xpOutReady[xp][channel][PORT_NORTH] =
              xpInReady[xp + CFG.meshX][channel][PORT_SOUTH];
          if (y > 0)
            xpOutReady[xp][channel][PORT_SOUTH] =
              xpInReady[xp - CFG.meshX][channel][PORT_NORTH];
          if ((x + 1) < CFG.meshX)
            xpOutReady[xp][channel][PORT_EAST] =
              xpInReady[xp + 1][channel][PORT_WEST];
          if (x > 0)
            xpOutReady[xp][channel][PORT_WEST] =
              xpInReady[xp - 1][channel][PORT_EAST];
          for (int unsigned device = 0; device < NUM_DEV_PORTS; device++)
            xpOutReady[xp][channel][NUM_NET_PORTS + device] =
              devOutReady[xp][channel][device];
        end
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
      .TOPOLOGY(MESH_2D),
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
