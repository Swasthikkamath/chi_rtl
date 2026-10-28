// System coherency interface of every RN-F and RN-D port (IHI 0050H B15).
//
// A Request Node enters system coherency by setting SYSCOREQ HIGH and leaves
// it by setting SYSCOREQ LOW; SYSCOACK follows in a four-phase handshake
// (B15.2). The interconnect side here:
//   connect     SYSCOACK goes HIGH the cycle after SYSCOREQ is seen HIGH,
//               without waiting for earlier snoops (B15.2.2). The node may
//               be snooped from the moment SYSCOREQ is HIGH.
//   disconnect  the moment SYSCOREQ is LOW the node gets no new snoop: the
//               Homes and MNs drop the snoops they had not sent and stop
//               tracking it. SYSCOACK goes LOW once every Home and MN reports
//               the node drained: no snoop to it outstanding and, for an
//               RN-F, no directory bit of it left (B15.2.2).
// With syscoEn 0 every node is always snoopable and SYSCOACK echoes
// SYSCOREQ, the behaviour of a design without the interface.
module chi_sysco #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  // RN-F and RN-D ports, RN-Fs first.
  parameter int unsigned NUM_COH = 1
) (
  input  logic clk,
  input  logic resetn,
  input  logic [NUM_COH-1:0] coReq,
  output logic [NUM_COH-1:0] coAck,
  output logic [NUM_COH-1:0] snoopable,
  input  logic [NUM_COH-1:0] drained
);
  logic [NUM_COH-1:0] ackReg;

  always_ff @(posedge clk) begin
    if (!resetn)
      ackReg <= '0;
    else
      for (int unsigned n = 0; n < NUM_COH; n++)
        if (coReq[n] && !ackReg[n])
          ackReg[n] <= 1'b1;
        else if (!coReq[n] && ackReg[n] && drained[n])
          ackReg[n] <= 1'b0;
  end

  always_comb begin
    coAck = CFG.syscoEn ? ackReg : coReq;
    snoopable = CFG.syscoEn ? coReq : '1;
  end
endmodule
