// One channel of one crosspoint.
//
// Ports 0 .. NUM_NET_PORTS-1 are network links to neighbouring crosspoints;
// the rest are device ports. Every input computes its output with
// chi_route_compute, every output arbitrates with chi_vc_arb (QoS, then age,
// then round-robin), and every output ends in an OUT_DEPTH-entry FIFO.
//
// The output FIFOs make the router fully registered: outValid and outFlit come
// from the FIFO, and inReady depends only on the requesting inputs and on the
// FIFO occupancy, never on outReady. There is therefore no combinational path
// from any output to any input, which is what the handshake discipline asks of
// every block (see the design specification, Section 2.8). Two entries keep a
// single input streaming at one flit per cycle.
//
// BUBBLE_FLOW applies bubble flow control to the network outputs, which the
// ring needs for deadlock freedom: a flit entering the ring from a device port
// may only be granted a network output with at least two free entries, a flit
// already on the ring with at least one. Ring injection therefore never takes
// the last free entry of a direction, so each direction of the ring always
// holds at least one empty entry and transit traffic can always advance.
//
// A flit whose TgtID names no attached node has no route. Holding it would
// block its input forever, so it is accepted, dropped, and reported on
// routeError instead.
module chi_router #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned XP_ID = 0,
  parameter int unsigned NUM_XP = chi_pkg::numXpOf(CFG),
  parameter int unsigned NUM_NET_PORTS = 4,
  parameter int unsigned NUM_DEV_PORTS = CFG.numDevPortsPerXp,
  parameter logic [NUM_XP*NUM_DEV_PORTS-1:0] POPULATED = '1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned OUT_DEPTH = 2,
  parameter bit BUBBLE_FLOW = 1'b0,
  parameter int unsigned NUM_PORTS = NUM_NET_PORTS + NUM_DEV_PORTS,
  parameter int unsigned COUNT_W = $clog2(OUT_DEPTH + 1)
) (
  input  logic                               clk,
  input  logic                               resetn,
  input  logic [NUM_PORTS-1:0]               inValid,
  output logic [NUM_PORTS-1:0]               inReady,
  input  chi_pkg::chi_noc_flit_t             inFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]               outValid,
  input  logic [NUM_PORTS-1:0]               outReady,
  output chi_pkg::chi_noc_flit_t             outFlit [NUM_PORTS-1:0],
  // Entries held in each output FIFO, exported for the bound ring assertions.
  output logic [NUM_PORTS-1:0][COUNT_W-1:0]  outCount,
  output logic                               routeError
);
  import chi_pkg::*;

  localparam int unsigned PTR_W = (OUT_DEPTH > 1) ? $clog2(OUT_DEPTH) : 1;

  logic [NUM_PORTS-1:0] inputRouteValid;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] inputRoute;
  logic [NUM_PORTS-1:0] dropInput;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeRequest;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeEligible;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0][3:0] routeQos;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeGrant;
  logic [NUM_PORTS-1:0] routeGrantValid;
  logic [NUM_PORTS-1:0] push;
  logic [NUM_PORTS-1:0] pop;
  chi_noc_flit_t pushFlit [NUM_PORTS-1:0];
  chi_noc_flit_t fifo [NUM_PORTS-1:0][OUT_DEPTH];
  logic [NUM_PORTS-1:0][PTR_W-1:0] readPointer;
  logic [NUM_PORTS-1:0][PTR_W-1:0] writePointer;
  logic [NUM_PORTS-1:0][COUNT_W-1:0] count;
  // Packed copy of the outputs for the bound assertions; binding an unpacked
  // array port is not portable across simulators.
  chi_noc_flit_t [NUM_PORTS-1:0] outFlitPacked;

  for (genvar inputIndex = 0;
       inputIndex < NUM_PORTS; inputIndex++) begin : routeComputes
    chi_route_compute #(
      .CFG(CFG),
      .XP_ID(XP_ID),
      .NUM_XP(NUM_XP),
      .NUM_NET_PORTS(NUM_NET_PORTS),
      .NUM_DEV_PORTS(NUM_DEV_PORTS),
      .POPULATED(POPULATED)
    ) routeCompute (
      .targetNodeId(inFlit[inputIndex].targetNodeId),
      .routeValid(inputRouteValid[inputIndex]),
      .route(inputRoute[inputIndex])
    );
  end

  // Forward direction: requests, eligibility, and the flit each granted
  // output will take. Nothing here reads a ready.
  always_comb begin
    routeRequest = '0;
    routeEligible = '0;
    routeQos = '0;
    dropInput = '0;
    for (int unsigned inputIndex = 0;
         inputIndex < NUM_PORTS; inputIndex++) begin
      dropInput[inputIndex] = inValid[inputIndex]
                              && !inputRouteValid[inputIndex];
    end
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++) begin
      for (int unsigned inputIndex = 0;
           inputIndex < NUM_PORTS; inputIndex++) begin
        routeRequest[outputIndex][inputIndex] =
          inValid[inputIndex] && inputRouteValid[inputIndex]
          && inputRoute[inputIndex][outputIndex];
        routeQos[outputIndex][inputIndex] = inFlit[inputIndex].qos;
        // An injection onto the ring is a device input granted a network
        // output, and needs two free entries; everything else needs one.
        if (BUBBLE_FLOW && (outputIndex < NUM_NET_PORTS)
            && (inputIndex >= NUM_NET_PORTS))
          routeEligible[outputIndex][inputIndex] =
            (int'(count[outputIndex]) + 2) <= OUT_DEPTH;
        else
          routeEligible[outputIndex][inputIndex] =
            int'(count[outputIndex]) < OUT_DEPTH;
      end
    end
  end

  always_comb begin
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++) begin
      push[outputIndex] = routeGrantValid[outputIndex];
      pushFlit[outputIndex] = '0;
      for (int unsigned inputIndex = 0;
           inputIndex < NUM_PORTS; inputIndex++) begin
        if (routeGrant[outputIndex][inputIndex])
          pushFlit[outputIndex] = inFlit[inputIndex];
      end
      // A flit leaving on a network link has crossed one more link.
      if (outputIndex < NUM_NET_PORTS)
        pushFlit[outputIndex].hops = pushFlit[outputIndex].hops + 8'd1;
    end
  end

  always_comb begin
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++) begin
      outValid[outputIndex] = count[outputIndex] != '0;
      outFlit[outputIndex] = fifo[outputIndex][readPointer[outputIndex]];
      outFlitPacked[outputIndex] = fifo[outputIndex][readPointer[outputIndex]];
      outCount[outputIndex] = count[outputIndex];
    end
    routeError = |dropInput;
  end

  // Backward direction: an input is ready when its output granted it, or when
  // it has no route and is being dropped. Grants were already masked by the
  // FIFO occupancy, so a grant is always taken.
  always_comb begin
    inReady = dropInput;
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++) begin
      for (int unsigned inputIndex = 0;
           inputIndex < NUM_PORTS; inputIndex++) begin
        if (routeGrant[outputIndex][inputIndex])
          inReady[inputIndex] = 1'b1;
      end
    end
  end

  always_comb begin
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++)
      pop[outputIndex] = outValid[outputIndex] && outReady[outputIndex];
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      count <= '0;
      readPointer <= '0;
      writePointer <= '0;
      for (int unsigned outputIndex = 0;
           outputIndex < NUM_PORTS; outputIndex++) begin
        for (int unsigned entry = 0; entry < OUT_DEPTH; entry++)
          fifo[outputIndex][entry] <= '0;
      end
    end else begin
      for (int unsigned outputIndex = 0;
           outputIndex < NUM_PORTS; outputIndex++) begin
        if (push[outputIndex]) begin
          fifo[outputIndex][writePointer[outputIndex]] <= pushFlit[outputIndex];
          if (int'(writePointer[outputIndex]) == (OUT_DEPTH - 1))
            writePointer[outputIndex] <= '0;
          else
            writePointer[outputIndex] <= writePointer[outputIndex] + 1'b1;
        end
        if (pop[outputIndex]) begin
          if (int'(readPointer[outputIndex]) == (OUT_DEPTH - 1))
            readPointer[outputIndex] <= '0;
          else
            readPointer[outputIndex] <= readPointer[outputIndex] + 1'b1;
        end
        if (push[outputIndex] && !pop[outputIndex])
          count[outputIndex] <= count[outputIndex] + 1'b1;
        else if (!push[outputIndex] && pop[outputIndex])
          count[outputIndex] <= count[outputIndex] - 1'b1;
      end
    end
  end

  for (genvar outputIndex = 0;
       outputIndex < NUM_PORTS; outputIndex++) begin : outputArbiters
    chi_vc_arb #(
      .NUM_REQUESTERS(NUM_PORTS),
      .AGE_LIMIT(AGE_LIMIT)
    ) vcArb (
      .clk(clk),
      .resetn(resetn),
      .request(routeRequest[outputIndex]),
      .eligible(routeEligible[outputIndex]),
      .qos(routeQos[outputIndex]),
      .ready(1'b1),
      .grant(routeGrant[outputIndex]),
      .grantValid(routeGrantValid[outputIndex])
    );
  end
endmodule
