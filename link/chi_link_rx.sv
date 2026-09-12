module chi_link_rx #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned FLIT_W = chi_pkg::reqFlitWidth(CFG),
  parameter int unsigned LCRD_DEPTH = CFG.lcrdDepth,
  parameter bit PARITY_EN = CFG.parityEn,
  parameter int unsigned PARITY_W = (FLIT_W + 7) / 8,
  parameter int unsigned PTR_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH),
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1)
) (
  input  logic                clk,
  input  logic                resetn,
  input  logic                LINKACTIVEREQ,
  output logic                LINKACTIVEACK,
  input  logic                FLITV,
  input  logic                FLITPEND,
  input  logic [FLIT_W-1:0]   FLIT,
  input  logic [PARITY_W-1:0] FLITP,
  output logic                LCRDV,
  output logic                internalValid,
  output logic [FLIT_W-1:0]   internalFlit,
  input  logic                internalReady,
  output logic                parityError,
  output logic                bufferOverflow,
  output logic [COUNT_W-1:0]  bufferCount,
  output logic [1:0]          linkState
);
  localparam logic [PTR_W-1:0] LAST_POINTER =
    PTR_W'(LCRD_DEPTH - 1);
  localparam logic [COUNT_W-1:0] LCRD_DEPTH_COUNT =
    COUNT_W'(LCRD_DEPTH);
  localparam logic [COUNT_W:0] LCRD_DEPTH_EXT =
    (COUNT_W + 1)'(LCRD_DEPTH);

  logic [FLIT_W-1:0] flitBuffer [0:LCRD_DEPTH-1];
  logic [PTR_W-1:0] writePointer;
  logic [PTR_W-1:0] readPointer;
  logic [COUNT_W-1:0] pendingCredits;
  logic [COUNT_W:0] pendingCreditsNext;
  logic linkRun;
  logic linkRunDelayed;
  logic pushFlit;
  logic popFlit;
  logic parityMismatch;

  always_comb begin
    internalValid = (bufferCount != '0);
    if (internalValid) begin
      internalFlit = flitBuffer[readPointer];
    end else begin
      internalFlit = '0;
    end
    pushFlit = linkRun && FLITV && (bufferCount < LCRD_DEPTH_COUNT);
    popFlit = internalValid && internalReady;
    bufferOverflow = linkRun && FLITV
                   && (bufferCount == LCRD_DEPTH_COUNT);
  end

  integer byteIndex;
  integer bitIndex;
  logic byteParity;
  always_comb begin
    parityMismatch = 1'b0;
    byteParity = 1'b0;
    if (PARITY_EN) begin
      for (byteIndex = 0; byteIndex < PARITY_W; byteIndex = byteIndex + 1) begin
        byteParity = 1'b0;
        for (bitIndex = 0; bitIndex < 8; bitIndex = bitIndex + 1) begin
          if (((byteIndex * 8) + bitIndex) < FLIT_W) begin
            byteParity = byteParity ^ FLIT[(byteIndex * 8) + bitIndex];
          end
        end
        parityMismatch = parityMismatch
                       || (byteParity != FLITP[byteIndex]);
      end
    end
  end

  always_comb begin
    LCRDV = LINKACTIVEACK && (pendingCredits != '0);
    pendingCreditsNext = {{1{1'b0}}, pendingCredits};
    if (linkRun && !linkRunDelayed) begin
      pendingCreditsNext = LCRD_DEPTH_EXT;
    end
    if (popFlit) begin
      pendingCreditsNext = pendingCreditsNext + 1'b1;
    end
    if (LCRDV && (pendingCreditsNext != '0)) begin
      pendingCreditsNext = pendingCreditsNext - 1'b1;
    end
    if (!LINKACTIVEACK && !linkRun) begin
      pendingCreditsNext = '0;
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      writePointer <= '0;
      readPointer <= '0;
      bufferCount <= '0;
      pendingCredits <= '0;
      linkRunDelayed <= 1'b0;
      parityError <= 1'b0;
    end else begin
      linkRunDelayed <= linkRun;
      pendingCredits <= pendingCreditsNext[COUNT_W-1:0];
      parityError <= pushFlit && parityMismatch;

      if (pushFlit) begin
        flitBuffer[writePointer] <= FLIT;
        if (writePointer == LAST_POINTER) begin
          writePointer <= '0;
        end else begin
          writePointer <= writePointer + 1'b1;
        end
      end

      if (popFlit) begin
        if (readPointer == LAST_POINTER) begin
          readPointer <= '0;
        end else begin
          readPointer <= readPointer + 1'b1;
        end
      end

      unique case ({pushFlit, popFlit})
        2'b10: bufferCount <= bufferCount + 1'b1;
        2'b01: bufferCount <= bufferCount - 1'b1;
        default: bufferCount <= bufferCount;
      endcase
    end
  end

  chi_link_fsm #(
    .INITIATOR(1'b0)
  ) activationFsm (
    .clk(clk),
    .resetn(resetn),
    .activate(1'b0),
    .deactivate(1'b0),
    .peerLinkActive(LINKACTIVEREQ),
    .creditsQuiescent((bufferCount == '0) && (pendingCredits == '0)),
    .linkActive(LINKACTIVEACK),
    .linkRun(linkRun),
    .state(linkState)
  );

  logic unusedFlitPending;
  always_comb begin
    unusedFlitPending = FLITPEND;
  end
endmodule
