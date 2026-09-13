module chi_mesh #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_PORTS-1:0] = '{default: '0},
  parameter chi_cfg_pkg::chi_mesh_placement_t
    PLACEMENTS [NUM_PORTS-1:0] = '{default: '0},
  parameter int unsigned NUM_XPS = CFG.meshX * CFG.meshY,
  parameter int unsigned NUM_XP_PORTS = 4 + CFG.numDevPortsPerXp
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
  output chi_pkg::chi_noc_flit_t                    datOutFlit [NUM_PORTS-1:0]
);
  import chi_pkg::*;

  logic [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0] xpInValid;
  logic [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0] xpInReady;
  chi_noc_flit_t xpInFlit [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0];
  logic [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0] xpOutValid;
  logic [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0] xpOutReady;
  chi_noc_flit_t xpOutFlit [NUM_XPS-1:0][3:0][NUM_XP_PORTS-1:0];

  // Each crosspoint registers its output, so the mesh has no combinational
  // path from any input to any output. Expressing that requires four blocks:
  // one per direction and side. Writing more than one side in a single block
  // would make every signal it drives appear to depend on every signal it
  // reads, which is what a linter reports as a combinational loop.
  always_comb begin
    xpInValid = '0;
    for (int unsigned channelIndex = 0; channelIndex < 4; channelIndex++) begin
      for (int unsigned xpIndex = 0; xpIndex < NUM_XPS; xpIndex++) begin
        for (int unsigned portIndex = 0;
             portIndex < NUM_XP_PORTS; portIndex++)
          xpInFlit[xpIndex][channelIndex][portIndex] = '0;
      end
    end

    for (int unsigned meshY = 0; meshY < CFG.meshY; meshY++) begin
      for (int unsigned meshX = 0; meshX < CFG.meshX; meshX++) begin
        int unsigned xpIndex;
        xpIndex = meshY * CFG.meshX + meshX;
        for (int unsigned channelIndex = 0;
             channelIndex < 4; channelIndex++) begin
          if ((meshY + 1) < CFG.meshY) begin
            xpInValid[xpIndex][channelIndex][0] =
              xpOutValid[xpIndex + CFG.meshX][channelIndex][1];
            xpInFlit[xpIndex][channelIndex][0] =
              xpOutFlit[xpIndex + CFG.meshX][channelIndex][1];
          end
          if (meshY > 0) begin
            xpInValid[xpIndex][channelIndex][1] =
              xpOutValid[xpIndex - CFG.meshX][channelIndex][0];
            xpInFlit[xpIndex][channelIndex][1] =
              xpOutFlit[xpIndex - CFG.meshX][channelIndex][0];
          end
          if ((meshX + 1) < CFG.meshX) begin
            xpInValid[xpIndex][channelIndex][2] =
              xpOutValid[xpIndex + 1][channelIndex][3];
            xpInFlit[xpIndex][channelIndex][2] =
              xpOutFlit[xpIndex + 1][channelIndex][3];
          end
          if (meshX > 0) begin
            xpInValid[xpIndex][channelIndex][3] =
              xpOutValid[xpIndex - 1][channelIndex][2];
            xpInFlit[xpIndex][channelIndex][3] =
              xpOutFlit[xpIndex - 1][channelIndex][2];
          end
        end
      end
    end

    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      int unsigned xpIndex;
      int unsigned devicePort;
      xpIndex = int'(PLACEMENTS[nodeIndex].meshY) * CFG.meshX
                + int'(PLACEMENTS[nodeIndex].meshX);
      devicePort = 4 + int'(PLACEMENTS[nodeIndex].devicePort);
      if (PLACEMENTS[nodeIndex].valid
          && (int'(PLACEMENTS[nodeIndex].meshX) < CFG.meshX)
          && (int'(PLACEMENTS[nodeIndex].meshY) < CFG.meshY)
          && (int'(PLACEMENTS[nodeIndex].devicePort)
              < CFG.numDevPortsPerXp)) begin
        xpInValid[xpIndex][CHI_CHANNEL_REQ][devicePort] = reqInValid[nodeIndex];
        xpInValid[xpIndex][CHI_CHANNEL_RSP][devicePort] = rspInValid[nodeIndex];
        xpInValid[xpIndex][CHI_CHANNEL_SNP][devicePort] = snpInValid[nodeIndex];
        xpInValid[xpIndex][CHI_CHANNEL_DAT][devicePort] = datInValid[nodeIndex];
        xpInFlit[xpIndex][CHI_CHANNEL_REQ][devicePort] = reqInFlit[nodeIndex];
        xpInFlit[xpIndex][CHI_CHANNEL_RSP][devicePort] = rspInFlit[nodeIndex];
        xpInFlit[xpIndex][CHI_CHANNEL_SNP][devicePort] = snpInFlit[nodeIndex];
        xpInFlit[xpIndex][CHI_CHANNEL_DAT][devicePort] = datInFlit[nodeIndex];
      end
    end
  end

  always_comb begin
    reqOutValid = '0;
    rspOutValid = '0;
    snpOutValid = '0;
    datOutValid = '0;
    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      reqOutFlit[nodeIndex] = '0;
      rspOutFlit[nodeIndex] = '0;
      snpOutFlit[nodeIndex] = '0;
      datOutFlit[nodeIndex] = '0;
    end

    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      int unsigned xpIndex;
      int unsigned devicePort;
      xpIndex = int'(PLACEMENTS[nodeIndex].meshY) * CFG.meshX
                + int'(PLACEMENTS[nodeIndex].meshX);
      devicePort = 4 + int'(PLACEMENTS[nodeIndex].devicePort);
      if (PLACEMENTS[nodeIndex].valid
          && (int'(PLACEMENTS[nodeIndex].meshX) < CFG.meshX)
          && (int'(PLACEMENTS[nodeIndex].meshY) < CFG.meshY)
          && (int'(PLACEMENTS[nodeIndex].devicePort)
              < CFG.numDevPortsPerXp)) begin
        reqOutValid[nodeIndex] = xpOutValid[xpIndex][CHI_CHANNEL_REQ][devicePort];
        rspOutValid[nodeIndex] = xpOutValid[xpIndex][CHI_CHANNEL_RSP][devicePort];
        snpOutValid[nodeIndex] = xpOutValid[xpIndex][CHI_CHANNEL_SNP][devicePort];
        datOutValid[nodeIndex] = xpOutValid[xpIndex][CHI_CHANNEL_DAT][devicePort];
        reqOutFlit[nodeIndex] = xpOutFlit[xpIndex][CHI_CHANNEL_REQ][devicePort];
        rspOutFlit[nodeIndex] = xpOutFlit[xpIndex][CHI_CHANNEL_RSP][devicePort];
        snpOutFlit[nodeIndex] = xpOutFlit[xpIndex][CHI_CHANNEL_SNP][devicePort];
        datOutFlit[nodeIndex] = xpOutFlit[xpIndex][CHI_CHANNEL_DAT][devicePort];
      end
    end
  end

  always_comb begin
    xpOutReady = '0;

    for (int unsigned meshY = 0; meshY < CFG.meshY; meshY++) begin
      for (int unsigned meshX = 0; meshX < CFG.meshX; meshX++) begin
        int unsigned xpIndex;
        xpIndex = meshY * CFG.meshX + meshX;
        for (int unsigned channelIndex = 0;
             channelIndex < 4; channelIndex++) begin
          if ((meshY + 1) < CFG.meshY)
            xpOutReady[xpIndex][channelIndex][0] =
              xpInReady[xpIndex + CFG.meshX][channelIndex][1];
          if (meshY > 0)
            xpOutReady[xpIndex][channelIndex][1] =
              xpInReady[xpIndex - CFG.meshX][channelIndex][0];
          if ((meshX + 1) < CFG.meshX)
            xpOutReady[xpIndex][channelIndex][2] =
              xpInReady[xpIndex + 1][channelIndex][3];
          if (meshX > 0)
            xpOutReady[xpIndex][channelIndex][3] =
              xpInReady[xpIndex - 1][channelIndex][2];
        end
      end
    end

    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      int unsigned xpIndex;
      int unsigned devicePort;
      xpIndex = int'(PLACEMENTS[nodeIndex].meshY) * CFG.meshX
                + int'(PLACEMENTS[nodeIndex].meshX);
      devicePort = 4 + int'(PLACEMENTS[nodeIndex].devicePort);
      if (PLACEMENTS[nodeIndex].valid
          && (int'(PLACEMENTS[nodeIndex].meshX) < CFG.meshX)
          && (int'(PLACEMENTS[nodeIndex].meshY) < CFG.meshY)
          && (int'(PLACEMENTS[nodeIndex].devicePort)
              < CFG.numDevPortsPerXp)) begin
        xpOutReady[xpIndex][CHI_CHANNEL_REQ][devicePort] = reqOutReady[nodeIndex];
        xpOutReady[xpIndex][CHI_CHANNEL_RSP][devicePort] = rspOutReady[nodeIndex];
        xpOutReady[xpIndex][CHI_CHANNEL_SNP][devicePort] = snpOutReady[nodeIndex];
        xpOutReady[xpIndex][CHI_CHANNEL_DAT][devicePort] = datOutReady[nodeIndex];
      end
    end
  end

  always_comb begin
    reqInReady = '0;
    rspInReady = '0;
    snpInReady = '0;
    datInReady = '0;

    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      int unsigned xpIndex;
      int unsigned devicePort;
      xpIndex = int'(PLACEMENTS[nodeIndex].meshY) * CFG.meshX
                + int'(PLACEMENTS[nodeIndex].meshX);
      devicePort = 4 + int'(PLACEMENTS[nodeIndex].devicePort);
      if (PLACEMENTS[nodeIndex].valid
          && (int'(PLACEMENTS[nodeIndex].meshX) < CFG.meshX)
          && (int'(PLACEMENTS[nodeIndex].meshY) < CFG.meshY)
          && (int'(PLACEMENTS[nodeIndex].devicePort)
              < CFG.numDevPortsPerXp)) begin
        reqInReady[nodeIndex] = xpInReady[xpIndex][CHI_CHANNEL_REQ][devicePort];
        rspInReady[nodeIndex] = xpInReady[xpIndex][CHI_CHANNEL_RSP][devicePort];
        snpInReady[nodeIndex] = xpInReady[xpIndex][CHI_CHANNEL_SNP][devicePort];
        datInReady[nodeIndex] = xpInReady[xpIndex][CHI_CHANNEL_DAT][devicePort];
      end
    end
  end

  for (genvar meshY = 0; meshY < CFG.meshY; meshY++) begin : meshRows
    for (genvar meshX = 0; meshX < CFG.meshX; meshX++) begin : meshColumns
      localparam int unsigned XP_INDEX = meshY * CFG.meshX + meshX;
      chi_mesh_xp #(
        .CFG(CFG),
        .CURRENT_X(meshX),
        .CURRENT_Y(meshY),
        .NUM_VALID_NODES(NUM_PORTS),
        .AGE_LIMIT(AGE_LIMIT),
        .VALID_NODE_IDS(NODE_IDS)
      ) xp (
        .clk(clk),
        .resetn(resetn),
        .inValid(xpInValid[XP_INDEX]),
        .inReady(xpInReady[XP_INDEX]),
        .inFlit(xpInFlit[XP_INDEX]),
        .outValid(xpOutValid[XP_INDEX]),
        .outReady(xpOutReady[XP_INDEX]),
        .outFlit(xpOutFlit[XP_INDEX])
      );
    end
  end
endmodule
