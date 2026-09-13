module chi_router #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned CURRENT_X = 0,
  parameter int unsigned CURRENT_Y = 0,
  parameter int unsigned NUM_VALID_NODES = 1,
  parameter int unsigned AGE_LIMIT = 16,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    VALID_NODE_IDS [NUM_VALID_NODES-1:0] = '{default: '0},
  parameter int unsigned NUM_PORTS = 4 + CFG.numDevPortsPerXp
) (
  input  logic                               clk,
  input  logic                               resetn,
  input  logic [NUM_PORTS-1:0]               inValid,
  output logic [NUM_PORTS-1:0]               inReady,
  input  chi_pkg::chi_noc_flit_t             inFlit [NUM_PORTS-1:0],
  output logic [NUM_PORTS-1:0]               outValid,
  input  logic [NUM_PORTS-1:0]               outReady,
  output chi_pkg::chi_noc_flit_t             outFlit [NUM_PORTS-1:0]
);
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeRequest;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0][3:0] routeQos;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] routeGrant;
  logic [NUM_PORTS-1:0] routeGrantValid;
  logic [NUM_PORTS-1:0] inputRouteValid;
  logic [NUM_PORTS-1:0][NUM_PORTS-1:0] inputRoute;
  logic [NUM_PORTS-1:0] outputBufferValid;
  logic [NUM_PORTS-1:0] outputBufferReady;
  chi_pkg::chi_noc_flit_t outputBufferFlit [NUM_PORTS-1:0];
  chi_pkg::chi_noc_flit_t selectedFlit [NUM_PORTS-1:0];

  for (genvar inputIndex = 0;
       inputIndex < NUM_PORTS; inputIndex++) begin : routeComputes
    chi_route_compute #(
      .CFG(CFG),
      .CURRENT_X(CURRENT_X),
      .CURRENT_Y(CURRENT_Y),
      .NUM_VALID_NODES(NUM_VALID_NODES),
      .VALID_NODE_IDS(VALID_NODE_IDS)
    ) routeCompute (
      .targetNodeId(inFlit[inputIndex].targetNodeId),
      .routeValid(inputRouteValid[inputIndex]),
      .route(inputRoute[inputIndex])
    );
  end

  always_comb begin
    routeRequest = '0;
    routeQos = '0;
    inReady = '0;
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_PORTS; outputIndex++) begin
      selectedFlit[outputIndex] = '0;
      outputBufferReady[outputIndex] = !outputBufferValid[outputIndex];
      outValid[outputIndex] = outputBufferValid[outputIndex];
      outFlit[outputIndex] = outputBufferFlit[outputIndex];
      for (int unsigned inputIndex = 0;
           inputIndex < NUM_PORTS; inputIndex++) begin
        routeRequest[outputIndex][inputIndex] =
          inValid[inputIndex] && inputRouteValid[inputIndex]
          && inputRoute[inputIndex][outputIndex];
        routeQos[outputIndex][inputIndex] = inFlit[inputIndex].qos;
        if (routeGrant[outputIndex][inputIndex]) begin
          selectedFlit[outputIndex] = inFlit[inputIndex];
          if (outputBufferReady[outputIndex])
            inReady[inputIndex] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      outputBufferValid <= '0;
      for (int unsigned outputIndex = 0;
           outputIndex < NUM_PORTS; outputIndex++) begin
        outputBufferFlit[outputIndex] <= '0;
      end
    end else begin
      for (int unsigned outputIndex = 0;
           outputIndex < NUM_PORTS; outputIndex++) begin
        if (outputBufferValid[outputIndex]) begin
          if (outReady[outputIndex]) begin
            outputBufferValid[outputIndex] <= 1'b0;
            outputBufferFlit[outputIndex] <= '0;
          end
        end else if (routeGrantValid[outputIndex]) begin
          outputBufferValid[outputIndex] <= routeGrantValid[outputIndex];
          outputBufferFlit[outputIndex] <= selectedFlit[outputIndex];
        end
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
      .qos(routeQos[outputIndex]),
      .ready(outputBufferReady[outputIndex]),
      .grant(routeGrant[outputIndex]),
      .grantValid(routeGrantValid[outputIndex])
    );
  end
endmodule
