module chi_link_rx #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned FLIT_W = chi_pkg::reqFlitWidth(CFG),
  parameter int unsigned LCRD_DEPTH = CFG.lcrdDepth,
  parameter bit PARITY_EN = CFG.parityEn,
  parameter int unsigned PARITY_W = (FLIT_W + 7) / 8,
  parameter int unsigned PTR_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH),
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1),
  parameter logic [FLIT_W-1:0] OPCODE_MASK = '0
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
  logic [COUNT_W-1:0] peerCredits;
  logic [COUNT_W:0] peerCreditsNext;
  logic linkRun;
  logic linkRunDelayed;
  logic linkAccept;
  logic lcrdReturnFlit;
  logic pushFlit;
  logic popFlit;
  logic parityMismatch;

  always_comb begin
    // Flits are accepted in the DEACTIVATE state as well as in RUN, both
    // because the Transmitter can still have a protocol flit in flight when it
    // deasserts LINKACTIVEREQ and because the L-Credit return flits arrive
    // only after that point (IHI 0050H B14.5).
    linkAccept = LINKACTIVEACK;
    // A zero Opcode identifies an LCrdReturn. It returns a credit instead of
    // carrying a message, so it is neither delivered upstream nor replaced by
    // a fresh credit (IHI 0050H B13.11).
    lcrdReturnFlit = (OPCODE_MASK != '0) && ((FLIT & OPCODE_MASK) == '0);
    internalValid = (bufferCount != '0);
    if (internalValid) begin
      internalFlit = flitBuffer[readPointer];
    end else begin
      internalFlit = '0;
    end
    pushFlit = linkAccept && FLITV && !lcrdReturnFlit
             && (bufferCount < LCRD_DEPTH_COUNT);
    bufferOverflow = linkAccept && FLITV && !lcrdReturnFlit
                   && (bufferCount == LCRD_DEPTH_COUNT);
  end

  // The pop decision consumes the downstream ready, so it is kept apart from
  // the block that presents the flit. Sharing a block would make the presented
  // valid appear to depend on the ready it drives.
  always_comb begin
    popFlit = internalValid && internalReady;
  end

  // Byte parity is odd (IHI 0050H B9.3.1): a byte and its check bit must
  // hold an odd number of ones between them, so their XOR must be 1.
  integer byteIndex;
  integer bitIndex;
  logic byteParity;
  always_comb begin
    parityMismatch = 1'b0;
    byteParity = 1'b0;
    if (PARITY_EN) begin
      for (byteIndex = 0; byteIndex < PARITY_W; byteIndex = byteIndex + 1) begin
        byteParity = FLITP[byteIndex];
        for (bitIndex = 0; bitIndex < 8; bitIndex = bitIndex + 1) begin
          if (((byteIndex * 8) + bitIndex) < FLIT_W) begin
            byteParity = byteParity ^ FLIT[(byteIndex * 8) + bitIndex];
          end
        end
        parityMismatch = parityMismatch || !byteParity;
      end
    end
  end

  // Credits are only issued while the link is running. The Receiver is
  // permitted to keep issuing them on entry to DEACTIVATE but must have
  // stopped before leaving it, and stopping at once meets that rule
  // (IHI 0050H B14.5.1).
  always_comb begin
    LCRDV = linkRun && (pendingCredits != '0);
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

  // Credits the peer Transmitter is holding. Each flit it sends spends one, and
  // a protocol flit earns a replacement once its buffer slot frees while an
  // LCrdReturn does not. The link must not return to STOP until every credit
  // has come back, which is what this count reaching zero means
  // (IHI 0050H B14.6.3.2).
  always_comb begin
    peerCreditsNext = {{1{1'b0}}, peerCredits};
    if (LCRDV) begin
      peerCreditsNext = peerCreditsNext + 1'b1;
    end
    if (linkAccept && FLITV && (peerCreditsNext != '0)) begin
      peerCreditsNext = peerCreditsNext - 1'b1;
    end
    if (!LINKACTIVEACK && !linkRun) begin
      peerCreditsNext = '0;
    end
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      writePointer <= '0;
      readPointer <= '0;
      bufferCount <= '0;
      pendingCredits <= '0;
      peerCredits <= '0;
      linkRunDelayed <= 1'b0;
      parityError <= 1'b0;
    end else begin
      linkRunDelayed <= linkRun;
      pendingCredits <= pendingCreditsNext[COUNT_W-1:0];
      peerCredits <= peerCreditsNext[COUNT_W-1:0];
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
    .creditsQuiescent((bufferCount == '0) && (peerCredits == '0)),
    .linkActive(LINKACTIVEACK),
    .linkRun(linkRun),
    .state(linkState)
  );

  logic unusedFlitPending;
  always_comb begin
    unusedFlitPending = FLITPEND;
  end
endmodule
