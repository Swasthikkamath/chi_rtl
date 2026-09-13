module chi_ring #(
  parameter int unsigned NUM_NODES = 4,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_NODES-1:0] = '{default: '0}
) (
  input  logic                                      clk,
  input  logic                                      resetn,

  input  logic [NUM_NODES-1:0]                      reqInValid,
  output logic [NUM_NODES-1:0]                      reqInReady,
  input  chi_pkg::chi_noc_flit_t                    reqInFlit [NUM_NODES-1:0],
  output logic [NUM_NODES-1:0]                      reqOutValid,
  input  logic [NUM_NODES-1:0]                      reqOutReady,
  output chi_pkg::chi_noc_flit_t                    reqOutFlit [NUM_NODES-1:0],

  input  logic [NUM_NODES-1:0]                      rspInValid,
  output logic [NUM_NODES-1:0]                      rspInReady,
  input  chi_pkg::chi_noc_flit_t                    rspInFlit [NUM_NODES-1:0],
  output logic [NUM_NODES-1:0]                      rspOutValid,
  input  logic [NUM_NODES-1:0]                      rspOutReady,
  output chi_pkg::chi_noc_flit_t                    rspOutFlit [NUM_NODES-1:0],

  input  logic [NUM_NODES-1:0]                      snpInValid,
  output logic [NUM_NODES-1:0]                      snpInReady,
  input  chi_pkg::chi_noc_flit_t                    snpInFlit [NUM_NODES-1:0],
  output logic [NUM_NODES-1:0]                      snpOutValid,
  input  logic [NUM_NODES-1:0]                      snpOutReady,
  output chi_pkg::chi_noc_flit_t                    snpOutFlit [NUM_NODES-1:0],

  input  logic [NUM_NODES-1:0]                      datInValid,
  output logic [NUM_NODES-1:0]                      datInReady,
  input  chi_pkg::chi_noc_flit_t                    datInFlit [NUM_NODES-1:0],
  output logic [NUM_NODES-1:0]                      datOutValid,
  input  logic [NUM_NODES-1:0]                      datOutReady,
  output chi_pkg::chi_noc_flit_t                    datOutFlit [NUM_NODES-1:0]
);
  import chi_pkg::*;

  localparam int unsigned CHANNEL_COUNT = 4;

  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] channelInValid;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] channelInReady;
  chi_noc_flit_t channelInFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] channelOutValid;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] channelOutReady;
  chi_noc_flit_t channelOutFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];

  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] clockwiseValid;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] counterclockwiseValid;
  chi_noc_flit_t clockwiseFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];
  chi_noc_flit_t counterclockwiseFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] clockwiseNextValid;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] counterclockwiseNextValid;
  chi_noc_flit_t clockwiseNextFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];
  chi_noc_flit_t counterclockwiseNextFlit [CHANNEL_COUNT-1:0][NUM_NODES-1:0];

  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] injectClockwiseRequest;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] injectCounterclockwiseRequest;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] injectLocalRequest;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeClockwiseTransit;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeClockwiseInjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeCounterclockwiseTransit;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeCounterclockwiseInjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeClockwiseEjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeCounterclockwiseEjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] takeLocalEjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] preferClockwiseInjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0] preferCounterclockwiseInjection;
  logic [CHANNEL_COUNT-1:0][NUM_NODES-1:0][1:0] ejectionRoundRobin;
  logic [CHANNEL_COUNT-1:0] rotateClockwise;
  logic [CHANNEL_COUNT-1:0] rotateCounterclockwise;

  always_comb begin
    channelInValid = '0;
    channelOutReady = '0;
    for (int unsigned nodeIndex = 0;
         nodeIndex < NUM_NODES; nodeIndex++) begin
      channelInValid[CHI_CHANNEL_REQ][nodeIndex] = reqInValid[nodeIndex];
      channelInValid[CHI_CHANNEL_RSP][nodeIndex] = rspInValid[nodeIndex];
      channelInValid[CHI_CHANNEL_SNP][nodeIndex] = snpInValid[nodeIndex];
      channelInValid[CHI_CHANNEL_DAT][nodeIndex] = datInValid[nodeIndex];
      channelInFlit[CHI_CHANNEL_REQ][nodeIndex] = reqInFlit[nodeIndex];
      channelInFlit[CHI_CHANNEL_RSP][nodeIndex] = rspInFlit[nodeIndex];
      channelInFlit[CHI_CHANNEL_SNP][nodeIndex] = snpInFlit[nodeIndex];
      channelInFlit[CHI_CHANNEL_DAT][nodeIndex] = datInFlit[nodeIndex];
      channelOutReady[CHI_CHANNEL_REQ][nodeIndex] = reqOutReady[nodeIndex];
      channelOutReady[CHI_CHANNEL_RSP][nodeIndex] = rspOutReady[nodeIndex];
      channelOutReady[CHI_CHANNEL_SNP][nodeIndex] = snpOutReady[nodeIndex];
      channelOutReady[CHI_CHANNEL_DAT][nodeIndex] = datOutReady[nodeIndex];
    end
  end

  always_comb begin
    injectClockwiseRequest = '0;
    injectCounterclockwiseRequest = '0;
    injectLocalRequest = '0;
    for (int unsigned channelIndex = 0;
         channelIndex < CHANNEL_COUNT; channelIndex++) begin
      for (int unsigned nodeIndex = 0;
           nodeIndex < NUM_NODES; nodeIndex++) begin
        int targetIndex;
        int clockwiseDistance;
        int counterclockwiseDistance;
        targetIndex = -1;
        clockwiseDistance = 0;
        counterclockwiseDistance = 0;
        for (int unsigned searchIndex = 0;
             searchIndex < NUM_NODES; searchIndex++) begin
          if (channelInFlit[channelIndex][nodeIndex].targetNodeId
              == NODE_IDS[searchIndex]) begin
            targetIndex = int'(searchIndex);
          end
        end
        if (channelInValid[channelIndex][nodeIndex] && (targetIndex >= 0)) begin
          if (targetIndex == int'(nodeIndex)) begin
            injectLocalRequest[channelIndex][nodeIndex] = 1'b1;
          end else begin
            if (targetIndex >= int'(nodeIndex)) begin
              clockwiseDistance = targetIndex - int'(nodeIndex);
            end else begin
              clockwiseDistance =
                targetIndex + int'(NUM_NODES) - int'(nodeIndex);
            end
            counterclockwiseDistance = int'(NUM_NODES) - clockwiseDistance;
            if (clockwiseDistance <= counterclockwiseDistance) begin
              injectClockwiseRequest[channelIndex][nodeIndex] = 1'b1;
            end else begin
              injectCounterclockwiseRequest[channelIndex][nodeIndex] = 1'b1;
            end
          end
        end
      end
    end
  end

  always_comb begin
    channelInReady = '0;
    channelOutValid = '0;
    rotateClockwise = '1;
    rotateCounterclockwise = '1;
    takeClockwiseTransit = '0;
    takeClockwiseInjection = '0;
    takeCounterclockwiseTransit = '0;
    takeCounterclockwiseInjection = '0;
    takeClockwiseEjection = '0;
    takeCounterclockwiseEjection = '0;
    takeLocalEjection = '0;
    for (int unsigned channelIndex = 0;
         channelIndex < CHANNEL_COUNT; channelIndex++) begin
      for (int unsigned nodeIndex = 0;
           nodeIndex < NUM_NODES; nodeIndex++) begin
        int previousNode;
        int nextNode;
        logic clockwiseTransitRequest;
        logic counterclockwiseTransitRequest;
        logic clockwiseEjectionRequest;
        logic counterclockwiseEjectionRequest;
        logic [2:0] ejectionRequest;
        logic ejectionWinnerFound;
        int ejectionCandidate;

        channelOutFlit[channelIndex][nodeIndex] = '0;
        previousNode = (nodeIndex == 0)
          ? int'(NUM_NODES - 1) : int'(nodeIndex - 1);
        nextNode = (nodeIndex == (NUM_NODES - 1))
          ? 0 : int'(nodeIndex + 1);
        clockwiseTransitRequest =
          clockwiseValid[channelIndex][previousNode]
          && (clockwiseFlit[channelIndex][previousNode].targetNodeId
              != NODE_IDS[nodeIndex]);
        counterclockwiseTransitRequest =
          counterclockwiseValid[channelIndex][nextNode]
          && (counterclockwiseFlit[channelIndex][nextNode].targetNodeId
              != NODE_IDS[nodeIndex]);

        if (!clockwiseValid[channelIndex][nodeIndex]) begin
          if (clockwiseTransitRequest
              && injectClockwiseRequest[channelIndex][nodeIndex]) begin
            if (preferClockwiseInjection[channelIndex][nodeIndex]) begin
              takeClockwiseInjection[channelIndex][nodeIndex] = 1'b1;
            end else begin
              takeClockwiseTransit[channelIndex][nodeIndex] = 1'b1;
            end
          end else if (clockwiseTransitRequest) begin
            takeClockwiseTransit[channelIndex][nodeIndex] = 1'b1;
          end else if (injectClockwiseRequest[channelIndex][nodeIndex]) begin
            takeClockwiseInjection[channelIndex][nodeIndex] = 1'b1;
          end
        end

        if (!counterclockwiseValid[channelIndex][nodeIndex]) begin
          if (counterclockwiseTransitRequest
              && injectCounterclockwiseRequest[channelIndex][nodeIndex]) begin
            if (preferCounterclockwiseInjection[channelIndex][nodeIndex]) begin
              takeCounterclockwiseInjection[channelIndex][nodeIndex] = 1'b1;
            end else begin
              takeCounterclockwiseTransit[channelIndex][nodeIndex] = 1'b1;
            end
          end else if (counterclockwiseTransitRequest) begin
            takeCounterclockwiseTransit[channelIndex][nodeIndex] = 1'b1;
          end else if (injectCounterclockwiseRequest[channelIndex][nodeIndex]) begin
            takeCounterclockwiseInjection[channelIndex][nodeIndex] = 1'b1;
          end
        end

        clockwiseEjectionRequest =
          clockwiseValid[channelIndex][previousNode]
          && (clockwiseFlit[channelIndex][previousNode].targetNodeId
              == NODE_IDS[nodeIndex]);
        counterclockwiseEjectionRequest =
          counterclockwiseValid[channelIndex][nextNode]
          && (counterclockwiseFlit[channelIndex][nextNode].targetNodeId
              == NODE_IDS[nodeIndex]);
        if (!clockwiseValid[channelIndex][previousNode]
            || clockwiseEjectionRequest) begin
          rotateClockwise[channelIndex] = 1'b0;
        end
        if (!counterclockwiseValid[channelIndex][nextNode]
            || counterclockwiseEjectionRequest) begin
          rotateCounterclockwise[channelIndex] = 1'b0;
        end
        ejectionRequest = {
          injectLocalRequest[channelIndex][nodeIndex],
          counterclockwiseEjectionRequest,
          clockwiseEjectionRequest
        };
        ejectionWinnerFound = 1'b0;
        ejectionCandidate = 0;
        for (int unsigned offset = 0; offset < 3; offset++) begin
          ejectionCandidate =
            int'(ejectionRoundRobin[channelIndex][nodeIndex]) + int'(offset);
          if (ejectionCandidate >= 3) begin
            ejectionCandidate = ejectionCandidate - 3;
          end
          if (!ejectionWinnerFound && ejectionRequest[ejectionCandidate]) begin
            ejectionWinnerFound = 1'b1;
            channelOutValid[channelIndex][nodeIndex] = 1'b1;
            case (ejectionCandidate)
              0: channelOutFlit[channelIndex][nodeIndex] =
                   clockwiseFlit[channelIndex][previousNode];
              1: channelOutFlit[channelIndex][nodeIndex] =
                   counterclockwiseFlit[channelIndex][nextNode];
              default: channelOutFlit[channelIndex][nodeIndex] =
                         channelInFlit[channelIndex][nodeIndex];
            endcase
            if (channelOutReady[channelIndex][nodeIndex]) begin
              case (ejectionCandidate)
                0: takeClockwiseEjection[channelIndex][nodeIndex] = 1'b1;
                1: takeCounterclockwiseEjection[channelIndex][nodeIndex] = 1'b1;
                default: takeLocalEjection[channelIndex][nodeIndex] = 1'b1;
              endcase
            end
          end
        end

        if (takeClockwiseInjection[channelIndex][nodeIndex]
            || takeCounterclockwiseInjection[channelIndex][nodeIndex]
            || takeLocalEjection[channelIndex][nodeIndex]) begin
          channelInReady[channelIndex][nodeIndex] = 1'b1;
        end
      end
    end
  end

  always_comb begin
    clockwiseNextValid = clockwiseValid;
    counterclockwiseNextValid = counterclockwiseValid;
    for (int unsigned channelIndex = 0;
         channelIndex < CHANNEL_COUNT; channelIndex++) begin
      for (int unsigned nodeIndex = 0;
           nodeIndex < NUM_NODES; nodeIndex++) begin
        int previousNode;
        int nextNode;
        previousNode = (nodeIndex == 0)
          ? int'(NUM_NODES - 1) : int'(nodeIndex - 1);
        nextNode = (nodeIndex == (NUM_NODES - 1))
          ? 0 : int'(nodeIndex + 1);
        clockwiseNextFlit[channelIndex][nodeIndex] =
          clockwiseFlit[channelIndex][nodeIndex];
        counterclockwiseNextFlit[channelIndex][nodeIndex] =
          counterclockwiseFlit[channelIndex][nodeIndex];

        if (takeClockwiseTransit[channelIndex][nodeIndex]) begin
          clockwiseNextValid[channelIndex][previousNode] = 1'b0;
          clockwiseNextValid[channelIndex][nodeIndex] = 1'b1;
          clockwiseNextFlit[channelIndex][nodeIndex] =
            clockwiseFlit[channelIndex][previousNode];
        end else if (takeClockwiseInjection[channelIndex][nodeIndex]) begin
          clockwiseNextValid[channelIndex][nodeIndex] = 1'b1;
          clockwiseNextFlit[channelIndex][nodeIndex] =
            channelInFlit[channelIndex][nodeIndex];
        end

        if (takeCounterclockwiseTransit[channelIndex][nodeIndex]) begin
          counterclockwiseNextValid[channelIndex][nextNode] = 1'b0;
          counterclockwiseNextValid[channelIndex][nodeIndex] = 1'b1;
          counterclockwiseNextFlit[channelIndex][nodeIndex] =
            counterclockwiseFlit[channelIndex][nextNode];
        end else if (takeCounterclockwiseInjection[channelIndex][nodeIndex]) begin
          counterclockwiseNextValid[channelIndex][nodeIndex] = 1'b1;
          counterclockwiseNextFlit[channelIndex][nodeIndex] =
            channelInFlit[channelIndex][nodeIndex];
        end

        if (takeClockwiseEjection[channelIndex][nodeIndex]) begin
          clockwiseNextValid[channelIndex][previousNode] = 1'b0;
        end
        if (takeCounterclockwiseEjection[channelIndex][nodeIndex]) begin
          counterclockwiseNextValid[channelIndex][nextNode] = 1'b0;
        end
      end
      if (rotateClockwise[channelIndex]) begin
        for (int unsigned nodeIndex = 0;
             nodeIndex < NUM_NODES; nodeIndex++) begin
          clockwiseNextFlit[channelIndex][nodeIndex] =
            clockwiseFlit[channelIndex][
              (nodeIndex == 0) ? (NUM_NODES - 1) : (nodeIndex - 1)];
        end
      end
      if (rotateCounterclockwise[channelIndex]) begin
        for (int unsigned nodeIndex = 0;
             nodeIndex < NUM_NODES; nodeIndex++) begin
          counterclockwiseNextFlit[channelIndex][nodeIndex] =
            counterclockwiseFlit[channelIndex][
              (nodeIndex == (NUM_NODES - 1)) ? 0 : (nodeIndex + 1)];
        end
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
    for (int unsigned nodeIndex = 0;
         nodeIndex < NUM_NODES; nodeIndex++) begin
      reqOutFlit[nodeIndex] = channelOutFlit[CHI_CHANNEL_REQ][nodeIndex];
      rspOutFlit[nodeIndex] = channelOutFlit[CHI_CHANNEL_RSP][nodeIndex];
      snpOutFlit[nodeIndex] = channelOutFlit[CHI_CHANNEL_SNP][nodeIndex];
      datOutFlit[nodeIndex] = channelOutFlit[CHI_CHANNEL_DAT][nodeIndex];
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      clockwiseValid <= '0;
      counterclockwiseValid <= '0;
      preferClockwiseInjection <= '0;
      preferCounterclockwiseInjection <= '0;
      ejectionRoundRobin <= '0;
      for (int unsigned channelIndex = 0;
           channelIndex < CHANNEL_COUNT; channelIndex++) begin
        for (int unsigned nodeIndex = 0;
             nodeIndex < NUM_NODES; nodeIndex++) begin
          clockwiseFlit[channelIndex][nodeIndex] <= '0;
          counterclockwiseFlit[channelIndex][nodeIndex] <= '0;
        end
      end
    end else begin
      clockwiseValid <= clockwiseNextValid;
      counterclockwiseValid <= counterclockwiseNextValid;
      for (int unsigned channelIndex = 0;
           channelIndex < CHANNEL_COUNT; channelIndex++) begin
        for (int unsigned nodeIndex = 0;
             nodeIndex < NUM_NODES; nodeIndex++) begin
          clockwiseFlit[channelIndex][nodeIndex] <=
            clockwiseNextFlit[channelIndex][nodeIndex];
          counterclockwiseFlit[channelIndex][nodeIndex] <=
            counterclockwiseNextFlit[channelIndex][nodeIndex];
          if (takeClockwiseTransit[channelIndex][nodeIndex]) begin
            preferClockwiseInjection[channelIndex][nodeIndex] <= 1'b1;
          end else if (takeClockwiseInjection[channelIndex][nodeIndex]) begin
            preferClockwiseInjection[channelIndex][nodeIndex] <= 1'b0;
          end
          if (takeCounterclockwiseTransit[channelIndex][nodeIndex]) begin
            preferCounterclockwiseInjection[channelIndex][nodeIndex] <= 1'b1;
          end else if (takeCounterclockwiseInjection[channelIndex][nodeIndex]) begin
            preferCounterclockwiseInjection[channelIndex][nodeIndex] <= 1'b0;
          end
          if (takeClockwiseEjection[channelIndex][nodeIndex]) begin
            ejectionRoundRobin[channelIndex][nodeIndex] <= 2'd1;
          end else if (takeCounterclockwiseEjection[channelIndex][nodeIndex]) begin
            ejectionRoundRobin[channelIndex][nodeIndex] <= 2'd2;
          end else if (takeLocalEjection[channelIndex][nodeIndex]) begin
            ejectionRoundRobin[channelIndex][nodeIndex] <= 2'd0;
          end
        end
      end
    end
  end
endmodule
