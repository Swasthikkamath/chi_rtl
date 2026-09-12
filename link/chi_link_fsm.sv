module chi_link_fsm #(
  parameter bit INITIATOR = 1'b1
) (
  input  logic       clk,
  input  logic       resetn,
  input  logic       activate,
  input  logic       deactivate,
  input  logic       peerLinkActive,
  input  logic       creditsQuiescent,
  output logic       linkActive,
  output logic       linkRun,
  output logic [1:0] state
);
  typedef enum logic [1:0] {
    STOP       = 2'b00,
    ACTIVATE   = 2'b01,
    RUN        = 2'b10,
    DEACTIVATE = 2'b11
  } chi_link_state_e;

  chi_link_state_e currentState;
  chi_link_state_e nextState;

  always_comb begin
    nextState = currentState;
    unique case (currentState)
      STOP: begin
        if ((INITIATOR && activate) || (!INITIATOR && peerLinkActive)) begin
          nextState = ACTIVATE;
        end
      end
      ACTIVATE: begin
        if (INITIATOR) begin
          if (deactivate) begin
            nextState = DEACTIVATE;
          end else if (peerLinkActive) begin
            nextState = RUN;
          end
        end else if (!peerLinkActive) begin
          nextState = DEACTIVATE;
        end else begin
          nextState = RUN;
        end
      end
      RUN: begin
        if ((INITIATOR && deactivate)
            || (!INITIATOR && !peerLinkActive)) begin
          nextState = DEACTIVATE;
        end
      end
      DEACTIVATE: begin
        if (creditsQuiescent
            && ((INITIATOR && !peerLinkActive) || !INITIATOR)) begin
          nextState = STOP;
        end
      end
      default: nextState = STOP;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      currentState <= STOP;
    end else begin
      currentState <= nextState;
    end
  end

  always_comb begin
    linkActive = 1'b0;
    linkRun = (currentState == RUN);
    if (INITIATOR) begin
      linkActive = (currentState == ACTIVATE) || (currentState == RUN);
    end else begin
      linkActive = (currentState == ACTIVATE) || (currentState == RUN)
                 || ((currentState == DEACTIVATE) && !creditsQuiescent);
    end
    state = currentState;
  end
endmodule
