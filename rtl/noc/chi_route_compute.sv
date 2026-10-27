// Route computation for one crosspoint input.
//
// The crosspoint routes on the NodeID alone, never on the address: the xpId
// field picks the destination crosspoint and the devicePort field picks the
// device port there (IHI 0050H B3.3 leaves the network to the
// implementation). The topology only changes how the next hop towards the
// destination crosspoint is chosen:
//
//   MESH_2D  dimension order: all X hops, then all Y hops. Network ports are
//            0 north (Y+1), 1 south (Y-1), 2 east (X+1), 3 west (X-1).
//   RING     the shorter direction, clockwise on a tie. Network port 0 is the
//            clockwise ring (towards XP_ID+1), port 1 the counter-clockwise.
//            The choice is stable along the route, so a flit never turns.
//   CROSSBAR one direct link to every other crosspoint. Network port p leads
//            to crosspoint p when p < XP_ID and to p+1 otherwise.
//
// A destination that is outside the fabric, or a device port with no node
// attached, has no route; routeValid stays low and the router drops the flit.
module chi_route_compute #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned XP_ID = 0,
  parameter int unsigned NUM_XP = chi_pkg::numXpOf(CFG),
  parameter int unsigned NUM_NET_PORTS = 4,
  parameter int unsigned NUM_DEV_PORTS = CFG.numDevPortsPerXp,
  parameter int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS,
  // One bit per device port of the whole fabric, at
  // xp * NUM_DEV_PORTS + devicePort, set where a node is attached.
  parameter logic [NUM_XP*NUM_DEV_PORTS-1:0] POPULATED = '1
) (
  input  logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] targetNodeId,
  output logic                                      routeValid,
  output logic [NUM_PORTS-1:0]                      route
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned MESH_X = (CFG.meshX > 0) ? CFG.meshX : 1;
  localparam int unsigned CURRENT_X = XP_ID % MESH_X;
  localparam int unsigned CURRENT_Y = XP_ID / MESH_X;

  int unsigned targetXp;
  int unsigned targetPort;
  int unsigned targetX;
  int unsigned targetY;
  int unsigned clockwise;
  logic targetExists;

  always_comb begin
    targetXp = nodeIdXpIndex(CFG, targetNodeId);
    targetPort = nodeIdDevicePort(CFG, targetNodeId);
    targetX = 0;
    targetY = 0;
    clockwise = 0;
    targetExists = (targetXp < NUM_XP) && (targetPort < NUM_DEV_PORTS);
    // The mesh X field is wider than meshX whenever meshX is not a power of
    // two, so an X value past the last column would otherwise alias a
    // crosspoint in the next row.
    if (CFG.topology == MESH_2D) begin
      targetX = nodeIdMeshX(CFG, targetNodeId);
      targetY = nodeIdMeshY(CFG, targetNodeId);
      targetExists = targetExists && (targetX < CFG.meshX)
                     && (targetY < CFG.meshY);
    end
    if (targetExists)
      targetExists = POPULATED[targetXp * NUM_DEV_PORTS + targetPort];

    routeValid = 1'b0;
    route = '0;
    if (targetExists) begin
      routeValid = 1'b1;
      if (targetXp == XP_ID) begin
        route[NUM_NET_PORTS + targetPort] = 1'b1;
      end else begin
        case (CFG.topology)
          MESH_2D: begin
            if (targetX > CURRENT_X)
              route[2] = 1'b1;
            else if (targetX < CURRENT_X)
              route[3] = 1'b1;
            else if (targetY > CURRENT_Y)
              route[0] = 1'b1;
            else
              route[1] = 1'b1;
          end
          RING: begin
            clockwise = (targetXp >= XP_ID) ? (targetXp - XP_ID)
                                            : (targetXp + NUM_XP - XP_ID);
            if (clockwise <= (NUM_XP - clockwise))
              route[0] = 1'b1;
            else
              route[1] = 1'b1;
          end
          default: begin
            if (targetXp < XP_ID)
              route[targetXp] = 1'b1;
            else
              route[targetXp - 1] = 1'b1;
          end
        endcase
      end
    end
  end
endmodule
