// Transport layer. The node-facing side is unchanged: NUM_PORTS node ports,
// indexed by node ordinal, on each of four independent channel networks. The
// fabric behind it is built from one parameterized crosspoint (chi_xp) for
// every topology; this block maps each node ordinal onto the crosspoint device
// port its placement names and selects the wiring wrapper:
//
//   MESH_2D   chi_mesh, meshX * meshY crosspoints, XY routing
//   RING      chi_ring, numXp crosspoints, shortest direction, bubble flow
//   CROSSBAR  chi_xbar, numXp fully connected crosspoints, one network hop
//
// NODE_IDS must encode each node's placement; chi_cfg_check in the product top
// verifies that, so the crosspoints can route on the NodeID fields alone.
module chi_noc_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_PORTS-1:0] = '{default: '0},
  parameter chi_cfg_pkg::chi_mesh_placement_t
    PLACEMENTS [NUM_PORTS-1:0] = '{default: '0},
  // Crosspoints, for the flit counts.
  parameter int unsigned NUM_XP_OUT =
    (chi_pkg::numXpOf(CFG) > 0) ? chi_pkg::numXpOf(CFG) : 1
) (
  input  logic                                      clk,
  input  logic                                      resetn,
  input  logic [NUM_PORTS-1:0]                      reqInValid,
  output logic [NUM_PORTS-1:0]                      reqInReady,
  input  chi_pkg::chi_noc_flit_t                    reqInFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]                      reqOutValid,
  input  logic [NUM_PORTS-1:0]                      reqOutReady,
  output chi_pkg::chi_noc_flit_t                    reqOutFlit [NUM_PORTS-1:0],
  input  logic [NUM_PORTS-1:0]                      rspInValid,
  output logic [NUM_PORTS-1:0]                      rspInReady,
  input  chi_pkg::chi_noc_flit_t                    rspInFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]                      rspOutValid,
  input  logic [NUM_PORTS-1:0]                      rspOutReady,
  output chi_pkg::chi_noc_flit_t                    rspOutFlit [NUM_PORTS-1:0],
  input  logic [NUM_PORTS-1:0]                      snpInValid,
  output logic [NUM_PORTS-1:0]                      snpInReady,
  input  chi_pkg::chi_noc_flit_t                    snpInFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]                      snpOutValid,
  input  logic [NUM_PORTS-1:0]                      snpOutReady,
  output chi_pkg::chi_noc_flit_t                    snpOutFlit [NUM_PORTS-1:0],
  input  logic [NUM_PORTS-1:0]                      datInValid,
  output logic [NUM_PORTS-1:0]                      datInReady,
  input  chi_pkg::chi_noc_flit_t                    datInFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]                      datOutValid,
  input  logic [NUM_PORTS-1:0]                      datOutReady,
  output chi_pkg::chi_noc_flit_t                    datOutFlit [NUM_PORTS-1:0],
  // A flit named a NodeID with no attached node and was dropped at its first
  // crosspoint rather than blocking the channel.
  output logic                                      routeError,
  // A flit is inside the fabric, held in a crosspoint FIFO; with no device
  // input valid as well, the fabric is empty.
  output logic                                      fabricBusy,
  // Flits each crosspoint took from and gave to its device ports this
  // cycle, per channel (REQ, RSP, SNP, DAT), for the PMU.
  output logic [NUM_XP_OUT-1:0][3:0][3:0]           xpInjected,
  output logic [NUM_XP_OUT-1:0][3:0][3:0]           xpEjected
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_XP = (numXpOf(CFG) > 0) ? numXpOf(CFG) : 1;
  localparam int unsigned NUM_DEV_PORTS =
    (CFG.numDevPortsPerXp > 0) ? CFG.numDevPortsPerXp : 1;

  typedef logic [NUM_XP*NUM_DEV_PORTS-1:0] populated_t;

  function automatic populated_t makePopulated();
    populated_t value;
    int unsigned xp;
    value = '0;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      xp = xpIndexOfPlacement(CFG, PLACEMENTS[node]);
      if (PLACEMENTS[node].valid && (xp < NUM_XP)
          && (int'(PLACEMENTS[node].devicePort) < NUM_DEV_PORTS))
        value[xp * NUM_DEV_PORTS + int'(PLACEMENTS[node].devicePort)] = 1'b1;
    end
    return value;
  endfunction

  localparam populated_t POPULATED = makePopulated();

  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0] devInValid;
  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0] devInReady;
  chi_noc_flit_t devInFlit [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0];
  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0] devOutValid;
  logic [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0] devOutReady;
  chi_noc_flit_t devOutFlit [NUM_XP-1:0][3:0][NUM_DEV_PORTS-1:0];

  // Node ports to device ports, in four blocks: device inputs forward, node
  // outputs forward, device outputs ready, node inputs ready.
  always_comb begin
    devInValid = '0;
    for (int unsigned xp = 0; xp < NUM_XP; xp++)
      for (int unsigned channel = 0; channel < 4; channel++)
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++)
          devInFlit[xp][channel][device] = '0;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      int unsigned xp;
      int unsigned device;
      xp = xpIndexOfPlacement(CFG, PLACEMENTS[node]);
      device = int'(PLACEMENTS[node].devicePort);
      if (PLACEMENTS[node].valid && (xp < NUM_XP) && (device < NUM_DEV_PORTS)) begin
        devInValid[xp][CHI_CHANNEL_REQ][device] = reqInValid[node];
        devInValid[xp][CHI_CHANNEL_RSP][device] = rspInValid[node];
        devInValid[xp][CHI_CHANNEL_SNP][device] = snpInValid[node];
        devInValid[xp][CHI_CHANNEL_DAT][device] = datInValid[node];
        devInFlit[xp][CHI_CHANNEL_REQ][device] = reqInFlit[node];
        devInFlit[xp][CHI_CHANNEL_RSP][device] = rspInFlit[node];
        devInFlit[xp][CHI_CHANNEL_SNP][device] = snpInFlit[node];
        devInFlit[xp][CHI_CHANNEL_DAT][device] = datInFlit[node];
      end
    end
  end

  always_comb begin
    reqOutValid = '0;
    rspOutValid = '0;
    snpOutValid = '0;
    datOutValid = '0;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      int unsigned xp;
      int unsigned device;
      reqOutFlit[node] = '0;
      rspOutFlit[node] = '0;
      snpOutFlit[node] = '0;
      datOutFlit[node] = '0;
      xp = xpIndexOfPlacement(CFG, PLACEMENTS[node]);
      device = int'(PLACEMENTS[node].devicePort);
      if (PLACEMENTS[node].valid && (xp < NUM_XP) && (device < NUM_DEV_PORTS)) begin
        reqOutValid[node] = devOutValid[xp][CHI_CHANNEL_REQ][device];
        rspOutValid[node] = devOutValid[xp][CHI_CHANNEL_RSP][device];
        snpOutValid[node] = devOutValid[xp][CHI_CHANNEL_SNP][device];
        datOutValid[node] = devOutValid[xp][CHI_CHANNEL_DAT][device];
        reqOutFlit[node] = devOutFlit[xp][CHI_CHANNEL_REQ][device];
        rspOutFlit[node] = devOutFlit[xp][CHI_CHANNEL_RSP][device];
        snpOutFlit[node] = devOutFlit[xp][CHI_CHANNEL_SNP][device];
        datOutFlit[node] = devOutFlit[xp][CHI_CHANNEL_DAT][device];
      end
    end
  end

  always_comb begin
    devOutReady = '0;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      int unsigned xp;
      int unsigned device;
      xp = xpIndexOfPlacement(CFG, PLACEMENTS[node]);
      device = int'(PLACEMENTS[node].devicePort);
      if (PLACEMENTS[node].valid && (xp < NUM_XP) && (device < NUM_DEV_PORTS)) begin
        devOutReady[xp][CHI_CHANNEL_REQ][device] = reqOutReady[node];
        devOutReady[xp][CHI_CHANNEL_RSP][device] = rspOutReady[node];
        devOutReady[xp][CHI_CHANNEL_SNP][device] = snpOutReady[node];
        devOutReady[xp][CHI_CHANNEL_DAT][device] = datOutReady[node];
      end
    end
  end

  always_comb begin
    reqInReady = '0;
    rspInReady = '0;
    snpInReady = '0;
    datInReady = '0;
    for (int unsigned node = 0; node < NUM_PORTS; node++) begin
      int unsigned xp;
      int unsigned device;
      xp = xpIndexOfPlacement(CFG, PLACEMENTS[node]);
      device = int'(PLACEMENTS[node].devicePort);
      if (PLACEMENTS[node].valid && (xp < NUM_XP) && (device < NUM_DEV_PORTS)) begin
        reqInReady[node] = devInReady[xp][CHI_CHANNEL_REQ][device];
        rspInReady[node] = devInReady[xp][CHI_CHANNEL_RSP][device];
        snpInReady[node] = devInReady[xp][CHI_CHANNEL_SNP][device];
        datInReady[node] = devInReady[xp][CHI_CHANNEL_DAT][device];
      end
    end
  end

  always_comb begin
    xpInjected = '0;
    xpEjected = '0;
    for (int unsigned xp = 0; (xp < NUM_XP) && (xp < NUM_XP_OUT); xp++)
      for (int unsigned channel = 0; channel < 4; channel++)
        for (int unsigned device = 0; device < NUM_DEV_PORTS; device++) begin
          if (devInValid[xp][channel][device] && devInReady[xp][channel][device])
            xpInjected[xp][channel] = xpInjected[xp][channel] + 4'd1;
          if (devOutValid[xp][channel][device] && devOutReady[xp][channel][device])
            xpEjected[xp][channel] = xpEjected[xp][channel] + 4'd1;
        end
  end

  if (CFG.topology == CROSSBAR) begin : crossbarTopology
    chi_xbar #(
      .CFG(CFG), .AGE_LIMIT(AGE_LIMIT), .OUT_DEPTH(OUT_DEPTH),
      .NUM_XP(NUM_XP), .NUM_DEV_PORTS(NUM_DEV_PORTS), .POPULATED(POPULATED)
    ) noc (
      .clk, .resetn, .devInValid, .devInReady, .devInFlit,
      .devOutValid, .devOutReady, .devOutFlit, .routeError,
      .busy(fabricBusy)
    );
  end else if (CFG.topology == RING) begin : ringTopology
    chi_ring #(
      .CFG(CFG), .AGE_LIMIT(AGE_LIMIT), .OUT_DEPTH(OUT_DEPTH),
      .NUM_XP(NUM_XP), .NUM_DEV_PORTS(NUM_DEV_PORTS), .POPULATED(POPULATED)
    ) noc (
      .clk, .resetn, .devInValid, .devInReady, .devInFlit,
      .devOutValid, .devOutReady, .devOutFlit, .routeError,
      .busy(fabricBusy)
    );
  end else begin : meshTopology
    chi_mesh #(
      .CFG(CFG), .AGE_LIMIT(AGE_LIMIT), .OUT_DEPTH(OUT_DEPTH),
      .NUM_XP(NUM_XP), .NUM_DEV_PORTS(NUM_DEV_PORTS), .POPULATED(POPULATED)
    ) noc (
      .clk, .resetn, .devInValid, .devInReady, .devInFlit,
      .devOutValid, .devOutReady, .devOutFlit, .routeError,
      .busy(fabricBusy)
    );
  end
endmodule
