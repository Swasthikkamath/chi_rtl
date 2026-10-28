// Endpoint Order across HN-Fs (IHI 0050H B2.7.5).
//
// Endpoint Order orders a Requester's requests to one endpoint address
// range. Behind the HN-Fs the endpoint is an SN-F, and several HN-Fs, each
// serving part of the address space, can share it, so the order cannot be
// kept inside one Home. A Requester sends its next Endpoint-ordered request
// only after the Home acknowledged the last (ReadReceipt or DBIDResp), so
// the order in which the Homes allocate them is the order it sent them.
//
// Each HN-F maps to one SN-F. When an HN-F allocates an Endpoint-ordered
// request it takes the next ticket of its {Requester, SN-F} pair; the
// request may start only when its ticket is the one served, and its
// retirement serves the next. So the requests reach the endpoint in the
// order the Requester sent them, whichever HN-F serves each.
module chi_eo_order #(
  parameter int unsigned NUM_HNF = 1,
  parameter int unsigned NUM_REQ = 1,
  parameter int unsigned NUM_SNF = 1,
  // The SN-F index each HN-F is striped to.
  parameter int unsigned HNF_SNF [NUM_HNF] = '{default:0},
  parameter int unsigned TICKET_W = 8,
  parameter int unsigned REQ_W = chi_pkg::clog2Min1(NUM_REQ)
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_HNF-1:0] allocValid,
  input  logic [NUM_HNF-1:0][REQ_W-1:0] allocReq,
  output logic [NUM_HNF-1:0][TICKET_W-1:0] allocTicket,
  // A Requester's Endpoint-ordered request retired at that HN-F.
  input  logic [NUM_HNF-1:0][NUM_REQ-1:0] retire,
  // The ticket served for each Requester at each HN-F's SN-F.
  output logic [NUM_HNF-1:0][NUM_REQ-1:0][TICKET_W-1:0] serving
);
  logic [NUM_REQ-1:0][NUM_SNF-1:0][TICKET_W-1:0] issued;
  logic [NUM_REQ-1:0][NUM_SNF-1:0][TICKET_W-1:0] served;

  // Two HN-Fs taking a ticket of one pair in the same cycle take them in
  // HN-F order. A Requester waiting for each acknowledgment never does so,
  // but the tickets stay distinct either way.
  always_comb
    for (int unsigned h = 0; h < NUM_HNF; h++) begin
      int unsigned ahead;
      ahead = 0;
      for (int unsigned g = 0; g < h; g++)
        if (allocValid[g] && (allocReq[g] == allocReq[h])
            && (HNF_SNF[g] == HNF_SNF[h]))
          ahead++;
      allocTicket[h] = issued[allocReq[h]][HNF_SNF[h]] + TICKET_W'(ahead);
      for (int unsigned q = 0; q < NUM_REQ; q++)
        serving[h][q] = served[q][HNF_SNF[h]];
    end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      issued <= '0;
      served <= '0;
    end else begin
      for (int unsigned q = 0; q < NUM_REQ; q++)
        for (int unsigned s = 0; s < NUM_SNF; s++) begin
          int unsigned taken;
          int unsigned done;
          taken = 0;
          done = 0;
          for (int unsigned h = 0; h < NUM_HNF; h++)
            if (HNF_SNF[h] == s) begin
              if (allocValid[h] && (int'(allocReq[h]) == q))
                taken++;
              if (retire[h][q])
                done++;
            end
          issued[q][s] <= issued[q][s] + TICKET_W'(taken);
          served[q][s] <= served[q][s] + TICKET_W'(done);
        end
    end
  end
endmodule
