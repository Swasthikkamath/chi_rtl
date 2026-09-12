module chi_noc_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_PORTS-1:0] = '{default: '0},
  parameter chi_cfg_pkg::chi_mesh_placement_t
    PLACEMENTS [NUM_PORTS-1:0] = '{default: '0}
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

  generate
    begin : chi_cfg_check
      initial begin
        if ((CFG.topology == chi_cfg_pkg::MESH_2D)
            && ((CFG.meshX == 0) || (CFG.meshY == 0)
                || (CFG.numDevPortsPerXp == 0)))
          $fatal(1, "Mesh dimensions and device-port count must be positive");
        for (int unsigned nodeIndex = 0;
             nodeIndex < NUM_PORTS; nodeIndex++) begin
          if (CFG.topology == chi_cfg_pkg::MESH_2D) begin
            if (!PLACEMENTS[nodeIndex].valid)
              $fatal(1, "Every mesh node requires a valid placement");
            if ((int'(PLACEMENTS[nodeIndex].meshX) >= CFG.meshX)
                || (int'(PLACEMENTS[nodeIndex].meshY) >= CFG.meshY)
                || (int'(PLACEMENTS[nodeIndex].devicePort)
                    >= CFG.numDevPortsPerXp))
              $fatal(1, "Mesh node placement is out of range");
            if ((nodeIdMeshX(CFG, NODE_IDS[nodeIndex])
                  != int'(PLACEMENTS[nodeIndex].meshX))
                || (nodeIdMeshY(CFG, NODE_IDS[nodeIndex])
                  != int'(PLACEMENTS[nodeIndex].meshY))
                || (nodeIdDevicePort(CFG, NODE_IDS[nodeIndex])
                  != int'(PLACEMENTS[nodeIndex].devicePort)))
              $fatal(1, "NodeID routing fields do not match mesh placement");
          end
          for (int unsigned otherIndex = nodeIndex + 1;
               otherIndex < NUM_PORTS; otherIndex++) begin
            if (NODE_IDS[nodeIndex] == NODE_IDS[otherIndex])
              $fatal(1, "NoC NodeIDs must be unique");
            if ((CFG.topology == chi_cfg_pkg::MESH_2D)
                && PLACEMENTS[nodeIndex].valid
                && PLACEMENTS[otherIndex].valid
                && (PLACEMENTS[nodeIndex].meshX
                    == PLACEMENTS[otherIndex].meshX)
                && (PLACEMENTS[nodeIndex].meshY
                    == PLACEMENTS[otherIndex].meshY)
                && (PLACEMENTS[nodeIndex].devicePort
                    == PLACEMENTS[otherIndex].devicePort))
              $fatal(1, "Mesh node placements must not collide");
          end
        end
      end
    end
  endgenerate

  if (CFG.topology == chi_cfg_pkg::CROSSBAR) begin : crossbarTopology
    chi_xbar #(
      .NUM_INPUTS(NUM_PORTS),
      .NUM_OUTPUTS(NUM_PORTS),
      .AGE_LIMIT(AGE_LIMIT),
      .OUTPUT_NODE_IDS(NODE_IDS)
    ) noc (
      .*
    );
  end else if (CFG.topology == chi_cfg_pkg::RING) begin : ringTopology
    chi_ring #(
      .NUM_NODES(NUM_PORTS),
      .NODE_IDS(NODE_IDS)
    ) noc (
      .*
    );
  end else begin : meshTopology
    chi_mesh #(
      .CFG(CFG),
      .NUM_PORTS(NUM_PORTS),
      .AGE_LIMIT(AGE_LIMIT),
      .NODE_IDS(NODE_IDS),
      .PLACEMENTS(PLACEMENTS)
    ) noc (
      .*
    );
  end
endmodule
