// Start permission for every POS entry.
//
// An HN-F orders transactions to one location by letting only the oldest of
// them run; a younger entry for the same location waits, already allocated,
// until the older one frees (IHI 0050H B4.11.2). The same check keeps a
// location that the directory is evicting, held by a victim entry, away from
// new transactions until the eviction is complete.
//
// Ordering between requests from one source (IHI 0050H B2.7.5):
//   Request Order   applies to one address, so the location check covers it.
//   Endpoint Order  applies to an endpoint address range. Every location this
//                   Home serves is behind one Subordinate, so the range is the
//                   whole Home: an Endpoint-ordered request waits for every
//                   older ordered request from the same source.
//
// Requests to different locations, and unordered requests, never wait for
// each other.
module chi_hazard #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned DEPTH = CFG.posEntries,
  parameter int unsigned KEY_W = CFG.addrW - 6,
  parameter int unsigned NUM_VB = 1
) (
  input  logic [DEPTH-1:0] active,
  input  logic [DEPTH-1:0][KEY_W-1:0] key,
  input  logic [DEPTH-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requester,
  input  chi_pkg::chi_order_e [DEPTH-1:0] order,
  input  logic [DEPTH-1:0][DEPTH-1:0] older,
  input  logic [NUM_VB-1:0] victimActive,
  input  logic [NUM_VB-1:0][KEY_W-1:0] victimKey,
  output logic [DEPTH-1:0] lineHazard,
  output logic [DEPTH-1:0] orderHazard,
  output logic [DEPTH-1:0] victimHazard,
  output logic [DEPTH-1:0] mayStart
);
  import chi_pkg::*;

  always_comb begin
    for (int unsigned entry = 0; entry < DEPTH; entry++) begin
      lineHazard[entry] = 1'b0;
      orderHazard[entry] = 1'b0;
      victimHazard[entry] = 1'b0;
      for (int unsigned other = 0; other < DEPTH; other++) begin
        if (active[other] && older[entry][other]) begin
          if (key[other] == key[entry])
            lineHazard[entry] = 1'b1;
          if ((order[entry] == ORDER_ENDPOINT)
              && (order[other] != ORDER_NONE)
              && (requester[other] == requester[entry]))
            orderHazard[entry] = 1'b1;
        end
      end
      for (int unsigned victim = 0; victim < NUM_VB; victim++)
        if (victimActive[victim] && (victimKey[victim] == key[entry]))
          victimHazard[entry] = 1'b1;
      mayStart[entry] = active[entry] && !lineHazard[entry]
                        && !orderHazard[entry] && !victimHazard[entry];
    end
  end
endmodule
