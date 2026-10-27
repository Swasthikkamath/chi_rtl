// Snoop issue for an HN-F.
//
// Every snooping owner — a POS entry or a victim-buffer entry — keeps its own
// vector of RN-Fs still to be snooped and of snoops awaiting a response, and
// collects its own responses; see chi_hnf_top. This block only chooses which
// (owner, RN-F) snoop goes out next: owners in round-robin order, and within
// an owner the lowest-numbered RN-F. The pointer stays on an owner until it
// has nothing left to send, so the snoops of one transaction leave back to
// back and are in flight together. A snoop carries its owner index as TxnID,
// so a response is matched to its owner by TxnID and to the RN-F by SrcID.
//
// MAX_OUTSTANDING (maxOutstandingSnoops) bounds the snoops in flight across
// all owners. The count is a register: an issue raises it, and every snoop
// the Home reports complete lowers it, a response without data and the last
// packet of a response with data possibly in the same cycle.
//
// issueValid never looks at issueReady (design specification, Section 2.8);
// a snoop is issued in a cycle where both are high.
module chi_snp_gen #(
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned NUM_RNF = 1,
  parameter int unsigned MAX_OUTSTANDING = 1,
  parameter int unsigned OWNER_W = chi_pkg::clog2Min1(NUM_OWNERS),
  parameter int unsigned RNF_W = chi_pkg::clog2Min1(NUM_RNF),
  parameter int unsigned COUNT_W = chi_pkg::clog2Min1(MAX_OUTSTANDING + 1)
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] toSend,
  // Snoops completed this cycle.
  input  logic rspComplete,
  input  logic datComplete,
  // The SNP output stage can take a flit this cycle.
  input  logic issueReady,
  output logic issueValid,
  output logic [OWNER_W-1:0] issueOwner,
  output logic [RNF_W-1:0] issueTarget,
  output logic [COUNT_W-1:0] outstanding
);
  logic [OWNER_W-1:0] nextOwner;
  logic ownerFound;
  logic issueFire;
  int unsigned candidate;

  always_comb begin
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

    issueValid = ownerFound && (int'(outstanding) < MAX_OUTSTANDING);
  end

  always_comb begin
    issueFire = issueValid && issueReady;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      nextOwner <= '0;
      outstanding <= '0;
    end else begin
      outstanding <= outstanding + COUNT_W'(issueFire)
                     - COUNT_W'(rspComplete) - COUNT_W'(datComplete);
      // Move past an owner once its last snoop has gone.
      if (issueFire
          && ((toSend[issueOwner] & ~(NUM_RNF'(1) << issueTarget)) == '0))
        nextOwner <= (int'(issueOwner) == (NUM_OWNERS - 1))
                     ? '0 : (issueOwner + 1'b1);
    end
  end
endmodule
