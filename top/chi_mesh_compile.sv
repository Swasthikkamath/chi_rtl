module chi_mesh_compile (
  input logic clk,
  input logic resetn
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_PORTS = 14;
  localparam chi_mesh_placement_t PLACEMENTS [NUM_PORTS-1:0] = '{
    defaultMeshPlacement(13), defaultMeshPlacement(12),
    defaultMeshPlacement(11), defaultMeshPlacement(10),
    defaultMeshPlacement(9),  defaultMeshPlacement(8),
    defaultMeshPlacement(7),  defaultMeshPlacement(6),
    defaultMeshPlacement(5),  defaultMeshPlacement(4),
    defaultMeshPlacement(3),  defaultMeshPlacement(2),
    defaultMeshPlacement(1),  defaultMeshPlacement(0)
  };
  localparam logic [CHI_MAX_NODEID_W-1:0] NODE_IDS [NUM_PORTS-1:0] = '{
    encodeNodeId(CHI_CFG_DEFAULT, 1, 1, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 1, 1, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 2, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 2, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 0, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 0, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 1, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 1, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 1, 0, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 0, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 1, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 1, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 1, 0, 1, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 0, 1, 0)
  };

  logic [NUM_PORTS-1:0] reqInValid, reqInReady, reqOutValid, reqOutReady;
  logic [NUM_PORTS-1:0] rspInValid, rspInReady, rspOutValid, rspOutReady;
  logic [NUM_PORTS-1:0] snpInValid, snpInReady, snpOutValid, snpOutReady;
  logic [NUM_PORTS-1:0] datInValid, datInReady, datOutValid, datOutReady;
  chi_noc_flit_t reqInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t reqOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t rspInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t rspOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t snpInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t snpOutFlit [NUM_PORTS-1:0];
  chi_noc_flit_t datInFlit [NUM_PORTS-1:0];
  chi_noc_flit_t datOutFlit [NUM_PORTS-1:0];

  always_comb begin
    reqInValid = '0;
    rspInValid = '0;
    snpInValid = '0;
    datInValid = '0;
    reqOutReady = '0;
    rspOutReady = '0;
    snpOutReady = '0;
    datOutReady = '0;
    for (int unsigned nodeIndex = 0; nodeIndex < NUM_PORTS; nodeIndex++) begin
      reqInFlit[nodeIndex] = '0;
      rspInFlit[nodeIndex] = '0;
      snpInFlit[nodeIndex] = '0;
      datInFlit[nodeIndex] = '0;
    end
  end

  chi_noc_top #(
    .CFG(CHI_CFG_DEFAULT),
    .NUM_PORTS(NUM_PORTS),
    .NODE_IDS(NODE_IDS),
    .PLACEMENTS(PLACEMENTS)
  ) noc (
    .*
  );
endmodule
