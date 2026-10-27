// Fabric assertions, bound to every channel router and to the ring.
//
// Router properties:
//   ROUTE_NEVER_SELECTS_NONEXISTENT_PORT  a computed route is one-hot and
//       names a network port that exists at this crosspoint or a device port
//       with a node attached.
//   EJECTS_AT_ENCODED_XP_AND_PORT  a flit leaving on a device port is at the
//       crosspoint and device port its TgtID encodes.
//   OUTPUT_STABLE_UNDER_BACKPRESSURE  a presented flit holds until taken.
//   ROUTE_LENGTH_BOUNDED  no flit ejects after more links than the longest
//       route the topology has.
//   MESH_NO_Y_TO_X_TURN  dimension-ordered routing: a flit that arrived on a
//       Y link never leaves on an X link.
//   RING_INJECTION_LEAVES_A_BUBBLE  a device input is granted a ring link
//       only when at least two entries are free.
//   NO_UNROUTABLE_FLIT  nothing reaches the fabric with a TgtID naming no
//       attached node.
//
// Ring property:
//   RING_DIRECTION_NEVER_FULL  every ring direction of every channel keeps at
//       least one free entry, which is the bubble invariant the ring relies
//       on for deadlock freedom.
module chi_router_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned XP_ID = 0,
  parameter int unsigned NUM_XP = 1,
  parameter int unsigned NUM_NET_PORTS = 4,
  parameter int unsigned NUM_DEV_PORTS = 2,
  parameter logic [NUM_XP*NUM_DEV_PORTS-1:0] POPULATED = '1,
  parameter int unsigned OUT_DEPTH = 2,
  parameter bit BUBBLE_FLOW = 1'b0,
  parameter int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS,
  parameter int unsigned COUNT_W = $clog2(OUT_DEPTH + 1)
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_PORTS-1:0] inValid,
  input logic [NUM_PORTS-1:0] outValid,
  input logic [NUM_PORTS-1:0] outReady,
  input chi_pkg::chi_noc_flit_t [NUM_PORTS-1:0] outFlitPacked,
  input logic [NUM_PORTS-1:0] inputRouteValid,
  input logic [NUM_PORTS-1:0][NUM_PORTS-1:0] inputRoute,
  input logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeGrant,
  input logic [NUM_PORTS-1:0][COUNT_W-1:0] count,
  input logic routeError
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned MESH_X = (CFG.meshX > 0) ? CFG.meshX : 1;
  localparam int unsigned CURRENT_X = XP_ID % MESH_X;
  localparam int unsigned CURRENT_Y = XP_ID / MESH_X;
  localparam int unsigned MAX_HOPS = maxXpHops(CFG);

  // Outputs that lead somewhere: the network ports this crosspoint really
  // has, and the device ports with a node attached.
  function automatic logic [NUM_PORTS-1:0] legalOutputs();
    logic [NUM_PORTS-1:0] mask;
    mask = '0;
    for (int unsigned port = 0; port < NUM_NET_PORTS; port++) begin
      if (CFG.topology == MESH_2D) begin
        case (port)
          0: mask[port] = (CURRENT_Y + 1) < CFG.meshY;
          1: mask[port] = CURRENT_Y > 0;
          2: mask[port] = (CURRENT_X + 1) < CFG.meshX;
          default: mask[port] = CURRENT_X > 0;
        endcase
      end else begin
        mask[port] = 1'b1;
      end
    end
    for (int unsigned device = 0; device < NUM_DEV_PORTS; device++)
      mask[NUM_NET_PORTS + device] = POPULATED[XP_ID * NUM_DEV_PORTS + device];
    return mask;
  endfunction

  localparam logic [NUM_PORTS-1:0] LEGAL_OUTPUTS = legalOutputs();
  localparam logic [NUM_DEV_PORTS-1:0] POPULATED_HERE =
    LEGAL_OUTPUTS[NUM_PORTS-1:NUM_NET_PORTS];

  for (genvar inputIndex = 0; inputIndex < NUM_PORTS;
       inputIndex++) begin : per_input
    ROUTE_NEVER_SELECTS_NONEXISTENT_PORT: assert property (
      @(posedge clk) disable iff (!resetn)
      inValid[inputIndex] && inputRouteValid[inputIndex]
        |-> $onehot(inputRoute[inputIndex])
            && ((inputRoute[inputIndex] & ~LEGAL_OUTPUTS) == '0));

    if ((CFG.topology == MESH_2D) && (inputIndex < 2)) begin : mesh_xy
      MESH_NO_Y_TO_X_TURN: assert property (
        @(posedge clk) disable iff (!resetn)
        inValid[inputIndex] && inputRouteValid[inputIndex]
          |-> !inputRoute[inputIndex][2] && !inputRoute[inputIndex][3]);
    end
  end

  for (genvar outputIndex = 0; outputIndex < NUM_PORTS;
       outputIndex++) begin : per_output
    OUTPUT_STABLE_UNDER_BACKPRESSURE: assert property (
      @(posedge clk) disable iff (!resetn)
      outValid[outputIndex] && !outReady[outputIndex]
        |=> outValid[outputIndex] && $stable(outFlitPacked[outputIndex]));

    OUTPUT_FIFO_IN_RANGE: assert property (
      @(posedge clk) disable iff (!resetn)
      int'(count[outputIndex]) <= OUT_DEPTH);

    if (outputIndex >= NUM_NET_PORTS) begin : device_output
      EJECTS_AT_ENCODED_XP_AND_PORT: assert property (
        @(posedge clk) disable iff (!resetn)
        outValid[outputIndex]
          |-> (nodeIdXpIndex(CFG, outFlitPacked[outputIndex].targetNodeId)
                 == XP_ID)
              && (nodeIdDevicePort(CFG, outFlitPacked[outputIndex].targetNodeId)
                 == (outputIndex - NUM_NET_PORTS)));

      ROUTE_LENGTH_BOUNDED: assert property (
        @(posedge clk) disable iff (!resetn)
        outValid[outputIndex]
          |-> int'(outFlitPacked[outputIndex].hops) <= MAX_HOPS);

      MAX_HOP_PATH: cover property (
        @(posedge clk) disable iff (!resetn)
        outValid[outputIndex] && outReady[outputIndex]
          && (int'(outFlitPacked[outputIndex].hops) == MAX_HOPS));
    end

    if (BUBBLE_FLOW && (outputIndex < NUM_NET_PORTS)) begin : ring_output
      for (genvar inputIndex = NUM_NET_PORTS; inputIndex < NUM_PORTS;
           inputIndex++) begin : injection
        RING_INJECTION_LEAVES_A_BUBBLE: assert property (
          @(posedge clk) disable iff (!resetn)
          routeGrant[outputIndex][inputIndex]
            |-> (int'(count[outputIndex]) + 2) <= OUT_DEPTH);
      end
    end
  end

  NO_UNROUTABLE_FLIT: assert property (
    @(posedge clk) disable iff (!resetn)
    !routeError);

  if (POPULATED_HERE != '0) begin : full_ejection
    ALL_DEVICE_PORTS_EJECT: cover property (
      @(posedge clk) disable iff (!resetn)
      ((outValid[NUM_PORTS-1:NUM_NET_PORTS] & outReady[NUM_PORTS-1:NUM_NET_PORTS])
         == POPULATED_HERE));
  end
endmodule

bind chi_router chi_router_sva #(
  .CFG(CFG),
  .XP_ID(XP_ID),
  .NUM_XP(NUM_XP),
  .NUM_NET_PORTS(NUM_NET_PORTS),
  .NUM_DEV_PORTS(NUM_DEV_PORTS),
  .POPULATED(POPULATED),
  .OUT_DEPTH(OUT_DEPTH),
  .BUBBLE_FLOW(BUBBLE_FLOW)
) chi_router_assertions (
  .clk(clk),
  .resetn(resetn),
  .inValid(inValid),
  .outValid(outValid),
  .outReady(outReady),
  .outFlitPacked(outFlitPacked),
  .inputRouteValid(inputRouteValid),
  .inputRoute(inputRoute),
  .routeGrant(routeGrant),
  .count(count),
  .routeError(routeError)
);

module chi_ring_sva #(
  parameter int unsigned NUM_XP = 2,
  parameter int unsigned NUM_PORTS = 4,
  parameter int unsigned OUT_DEPTH = 2,
  parameter int unsigned COUNT_W = $clog2(OUT_DEPTH + 1)
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0][COUNT_W-1:0] xpOutCount
);
  function automatic int unsigned occupancy(
    input logic [NUM_XP-1:0][3:0][NUM_PORTS-1:0][COUNT_W-1:0] counts,
    input int unsigned channel,
    input int unsigned direction
  );
    int unsigned total;
    total = 0;
    for (int unsigned xp = 0; xp < NUM_XP; xp++)
      total += int'(counts[xp][channel][direction]);
    return total;
  endfunction

  for (genvar channel = 0; channel < 4; channel++) begin : per_channel
    for (genvar direction = 0; direction < 2; direction++) begin : per_direction
      RING_DIRECTION_NEVER_FULL: assert property (
        @(posedge clk) disable iff (!resetn)
        occupancy(xpOutCount, channel, direction) < (NUM_XP * OUT_DEPTH));
    end
  end
endmodule

bind chi_ring chi_ring_sva #(
  .NUM_XP(NUM_XP),
  .NUM_PORTS(NUM_PORTS),
  .OUT_DEPTH(OUT_DEPTH),
  .COUNT_W(COUNT_W)
) chi_ring_assertions (
  .clk(clk),
  .resetn(resetn),
  .xpOutCount(xpOutCount)
);
