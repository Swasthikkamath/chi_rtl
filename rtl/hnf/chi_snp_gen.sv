// Snoop issue for an HN-F.
//
// Every snooping owner — a POS entry or a victim-buffer entry — keeps its own
// vector of RN-Fs still to be snooped and of snoops awaiting a response, and
// collects its own responses; see chi_hnf_top. This block only chooses which
// (owner, RN-F) snoop goes out next: owners in round-robin order, and within
// an owner the lowest-numbered RN-F. A snoop carries its owner index as TxnID,
// so a response is matched to its owner by TxnID and to the RN-F by SrcID.
//
// MAX_OUTSTANDING bounds the snoops in flight across all owners. With 1 the
// Home snoops strictly one RN-F at a time.
module chi_snp_gen #(
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned NUM_RNF = 1,
  parameter int unsigned MAX_OUTSTANDING = 1,
  parameter int unsigned OWNER_W = chi_pkg::clog2Min1(NUM_OWNERS),
  parameter int unsigned RNF_W = chi_pkg::clog2Min1(NUM_RNF)
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] toSend,
  input  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] pending,
  // The SNP output stage can take a flit this cycle.
  input  logic issueReady,
  output logic issueValid,
  output logic [OWNER_W-1:0] issueOwner,
  output logic [RNF_W-1:0] issueTarget,
  output logic [31:0] outstanding
);
  logic [OWNER_W-1:0] nextOwner;
  logic ownerFound;
  int unsigned candidate;
  int unsigned inFlight;

  always_comb begin
    inFlight = 0;
    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++)
      for (int unsigned rnf = 0; rnf < NUM_RNF; rnf++)
        if (pending[owner][rnf])
          inFlight++;
    outstanding = inFlight;

    ownerFound = 1'b0;
    issueOwner = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < NUM_OWNERS; offset++) begin
      candidate = int'(nextOwner) + offset;
      if (candidate >= NUM_OWNERS)
        candidate = candidate - NUM_OWNERS;
      if (!ownerFound && (toSend[candidate] != '0)) begin
        ownerFound = 1'b1;
        issueOwner = OWNER_W'(candidate);
      end
    end

    issueTarget = '0;
    for (int unsigned rnf = NUM_RNF; rnf > 0; rnf--)
      if (toSend[issueOwner][rnf-1])
        issueTarget = RNF_W'(rnf - 1);

    issueValid = ownerFound && (inFlight < MAX_OUTSTANDING) && issueReady;
  end

  // The round-robin pointer moves past an owner once it has nothing left to
  // send, so one owner's snoops go out back to back.
  always_ff @(posedge clk) begin
    if (!resetn) begin
      nextOwner <= '0;
    end else if (issueValid
                 && ((toSend[issueOwner] & ~(NUM_RNF'(1) << issueTarget)) == '0)) begin
      nextOwner <= (int'(issueOwner) == (NUM_OWNERS - 1))
                   ? '0 : (issueOwner + 1'b1);
    end
  end
endmodule
