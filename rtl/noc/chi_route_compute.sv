module chi_route_compute #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned CURRENT_X = 0,
  parameter int unsigned CURRENT_Y = 0,
  parameter int unsigned NUM_VALID_NODES = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    VALID_NODE_IDS [NUM_VALID_NODES-1:0] = '{default: '0}
) (
  input  logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] targetNodeId,
  output logic                                      routeValid,
  output logic [3+CFG.numDevPortsPerXp:0]          route
);
  import chi_pkg::*;

  int targetX;
  int targetY;
  int targetDevicePort;
  logic targetKnown;

  always_comb begin
    targetX = nodeIdMeshX(CFG, targetNodeId);
    targetY = nodeIdMeshY(CFG, targetNodeId);
    targetDevicePort = nodeIdDevicePort(CFG, targetNodeId);
    targetKnown = 1'b0;
    routeValid = 1'b0;
    route = '0;

    for (int unsigned nodeIndex = 0;
         nodeIndex < NUM_VALID_NODES; nodeIndex++) begin
      if (targetNodeId == VALID_NODE_IDS[nodeIndex])
        targetKnown = 1'b1;
    end

    if (targetKnown && (targetX < CFG.meshX) && (targetY < CFG.meshY)) begin
      if (targetX > int'(CURRENT_X)) begin
        route[2] = 1'b1;
        routeValid = 1'b1;
      end else if (targetX < int'(CURRENT_X)) begin
        route[3] = 1'b1;
        routeValid = 1'b1;
      end else if (targetY > int'(CURRENT_Y)) begin
        route[0] = 1'b1;
        routeValid = 1'b1;
      end else if (targetY < int'(CURRENT_Y)) begin
        route[1] = 1'b1;
        routeValid = 1'b1;
      end else if (targetDevicePort < CFG.numDevPortsPerXp) begin
        route[4 + targetDevicePort] = 1'b1;
        routeValid = 1'b1;
      end
    end
  end
endmodule
