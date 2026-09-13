module chi_xbar #(
  parameter int unsigned NUM_INPUTS = 4,
  parameter int unsigned NUM_OUTPUTS = 4,
  parameter int unsigned AGE_LIMIT = 16,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    OUTPUT_NODE_IDS [NUM_OUTPUTS-1:0] = '{default: '0}
) (
  input  logic                                      clk,
  input  logic                                      resetn,

  input  logic [NUM_INPUTS-1:0]                     reqInValid,
  output logic [NUM_INPUTS-1:0]                     reqInReady,
  input  chi_pkg::chi_noc_flit_t                    reqInFlit [NUM_INPUTS-1:0],
  output logic [NUM_OUTPUTS-1:0]                    reqOutValid,
  input  logic [NUM_OUTPUTS-1:0]                    reqOutReady,
  output chi_pkg::chi_noc_flit_t                    reqOutFlit [NUM_OUTPUTS-1:0],

  input  logic [NUM_INPUTS-1:0]                     rspInValid,
  output logic [NUM_INPUTS-1:0]                     rspInReady,
  input  chi_pkg::chi_noc_flit_t                    rspInFlit [NUM_INPUTS-1:0],
  output logic [NUM_OUTPUTS-1:0]                    rspOutValid,
  input  logic [NUM_OUTPUTS-1:0]                    rspOutReady,
  output chi_pkg::chi_noc_flit_t                    rspOutFlit [NUM_OUTPUTS-1:0],

  input  logic [NUM_INPUTS-1:0]                     snpInValid,
  output logic [NUM_INPUTS-1:0]                     snpInReady,
  input  chi_pkg::chi_noc_flit_t                    snpInFlit [NUM_INPUTS-1:0],
  output logic [NUM_OUTPUTS-1:0]                    snpOutValid,
  input  logic [NUM_OUTPUTS-1:0]                    snpOutReady,
  output chi_pkg::chi_noc_flit_t                    snpOutFlit [NUM_OUTPUTS-1:0],

  input  logic [NUM_INPUTS-1:0]                     datInValid,
  output logic [NUM_INPUTS-1:0]                     datInReady,
  input  chi_pkg::chi_noc_flit_t                    datInFlit [NUM_INPUTS-1:0],
  output logic [NUM_OUTPUTS-1:0]                    datOutValid,
  input  logic [NUM_OUTPUTS-1:0]                    datOutReady,
  output chi_pkg::chi_noc_flit_t                    datOutFlit [NUM_OUTPUTS-1:0]
);
  import chi_pkg::*;

  localparam int unsigned CHANNEL_COUNT = 4;

  logic [CHANNEL_COUNT-1:0][NUM_INPUTS-1:0] channelInValid;
  logic [CHANNEL_COUNT-1:0][NUM_INPUTS-1:0] channelInReady;
  chi_noc_flit_t channelInFlit [CHANNEL_COUNT-1:0][NUM_INPUTS-1:0];
  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0] channelOutValid;
  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0] channelOutReady;
  chi_noc_flit_t channelOutFlit [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0];

  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0][NUM_INPUTS-1:0]
    routeRequest;
  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0][NUM_INPUTS-1:0][3:0]
    routeQos;
  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0][NUM_INPUTS-1:0]
    routeGrant;
  logic [CHANNEL_COUNT-1:0][NUM_OUTPUTS-1:0] routeGrantValid;

  always_comb begin
    channelInValid = '0;
    channelOutReady = '0;
    for (int unsigned inputIndex = 0;
         inputIndex < NUM_INPUTS; inputIndex++) begin
      channelInValid[CHI_CHANNEL_REQ][inputIndex] = reqInValid[inputIndex];
      channelInValid[CHI_CHANNEL_RSP][inputIndex] = rspInValid[inputIndex];
      channelInValid[CHI_CHANNEL_SNP][inputIndex] = snpInValid[inputIndex];
      channelInValid[CHI_CHANNEL_DAT][inputIndex] = datInValid[inputIndex];
      channelInFlit[CHI_CHANNEL_REQ][inputIndex] = reqInFlit[inputIndex];
      channelInFlit[CHI_CHANNEL_RSP][inputIndex] = rspInFlit[inputIndex];
      channelInFlit[CHI_CHANNEL_SNP][inputIndex] = snpInFlit[inputIndex];
      channelInFlit[CHI_CHANNEL_DAT][inputIndex] = datInFlit[inputIndex];
    end
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_OUTPUTS; outputIndex++) begin
      channelOutReady[CHI_CHANNEL_REQ][outputIndex] =
        reqOutReady[outputIndex];
      channelOutReady[CHI_CHANNEL_RSP][outputIndex] =
        rspOutReady[outputIndex];
      channelOutReady[CHI_CHANNEL_SNP][outputIndex] =
        snpOutReady[outputIndex];
      channelOutReady[CHI_CHANNEL_DAT][outputIndex] =
        datOutReady[outputIndex];
    end
  end

  always_comb begin
    routeRequest = '0;
    routeQos = '0;
    channelInReady = '0;
    channelOutValid = '0;
    for (int unsigned channelIndex = 0;
         channelIndex < CHANNEL_COUNT; channelIndex++) begin
      for (int unsigned outputIndex = 0;
           outputIndex < NUM_OUTPUTS; outputIndex++) begin
        channelOutFlit[channelIndex][outputIndex] = '0;
        for (int unsigned inputIndex = 0;
             inputIndex < NUM_INPUTS; inputIndex++) begin
          if (channelInValid[channelIndex][inputIndex]
              && (channelInFlit[channelIndex][inputIndex].targetNodeId
                  == OUTPUT_NODE_IDS[outputIndex])) begin
            routeRequest[channelIndex][outputIndex][inputIndex] = 1'b1;
            routeQos[channelIndex][outputIndex][inputIndex] =
              channelInFlit[channelIndex][inputIndex].qos;
          end

          if (routeGrant[channelIndex][outputIndex][inputIndex]) begin
            channelOutFlit[channelIndex][outputIndex] =
              channelInFlit[channelIndex][inputIndex];
            if (channelOutReady[channelIndex][outputIndex]) begin
              channelInReady[channelIndex][inputIndex] = 1'b1;
            end
          end
        end
        channelOutValid[channelIndex][outputIndex] =
          routeGrantValid[channelIndex][outputIndex];
      end
    end
  end

  always_comb begin
    reqInReady = channelInReady[CHI_CHANNEL_REQ];
    rspInReady = channelInReady[CHI_CHANNEL_RSP];
    snpInReady = channelInReady[CHI_CHANNEL_SNP];
    datInReady = channelInReady[CHI_CHANNEL_DAT];
    reqOutValid = channelOutValid[CHI_CHANNEL_REQ];
    rspOutValid = channelOutValid[CHI_CHANNEL_RSP];
    snpOutValid = channelOutValid[CHI_CHANNEL_SNP];
    datOutValid = channelOutValid[CHI_CHANNEL_DAT];
    for (int unsigned outputIndex = 0;
         outputIndex < NUM_OUTPUTS; outputIndex++) begin
      reqOutFlit[outputIndex] =
        channelOutFlit[CHI_CHANNEL_REQ][outputIndex];
      rspOutFlit[outputIndex] =
        channelOutFlit[CHI_CHANNEL_RSP][outputIndex];
      snpOutFlit[outputIndex] =
        channelOutFlit[CHI_CHANNEL_SNP][outputIndex];
      datOutFlit[outputIndex] =
        channelOutFlit[CHI_CHANNEL_DAT][outputIndex];
    end
  end

  for (genvar channelIndex = 0;
       channelIndex < CHANNEL_COUNT; channelIndex++) begin : channelArbiters
    for (genvar outputIndex = 0;
         outputIndex < NUM_OUTPUTS; outputIndex++) begin : outputArbiters
      chi_vc_arb #(
        .NUM_REQUESTERS(NUM_INPUTS),
        .AGE_LIMIT(AGE_LIMIT)
      ) vcArb (
        .clk(clk),
        .resetn(resetn),
        .request(routeRequest[channelIndex][outputIndex]),
        .qos(routeQos[channelIndex][outputIndex]),
        .ready(channelOutReady[channelIndex][outputIndex]),
        .grant(routeGrant[channelIndex][outputIndex]),
        .grantValid(routeGrantValid[channelIndex][outputIndex])
      );
    end
  end
endmodule
