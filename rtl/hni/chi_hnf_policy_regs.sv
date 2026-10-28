// Run-time HN-F policy registers, one APB4 block of 256 bytes.
//
// Software stages a policy per HN-F and then commits all of them at once. A
// commit is refused with PSLVERR unless the fabric is quiescent, so no
// transaction is admitted under one policy and completed under another. Every
// policy bit only narrows what the elaboration-time configuration allows: the
// HN-F ANDs it with the global enable in chi_cfg_t and with the capability of
// the node involved.
//
// The register map and the security rule are implementation defined; CHI
// defines no register interface. Writes need a Root access with RME
// (PNSE == 1, PPROT[1] == 0) and a Secure access without it, the same rule as
// the region editor in chi_cfg_slave. Reads are unrestricted.
//
//   0x00 SELECT  RW  HN-F index the next two registers refer to
//   0x04 STAGED  RW  staged policy of the selected HN-F (chi_hnf_policy_t)
//   0x08 ACTIVE  RO  policy the selected HN-F is using now
//   0x0C COMMIT  WO  PSTRB[0] with PWDATA[0] = 1 copies every staged policy
//                    into the active set, provided the fabric is quiescent
module chi_hnf_policy_regs #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_HNF = (CFG.numHnf > 0) ? CFG.numHnf : 1,
  parameter chi_cfg_pkg::chi_hnf_policy_t RESET_POLICY =
    chi_cfg_pkg::CHI_HNF_POLICY_DEFAULT
) (
  input  logic PCLK,
  input  logic PRESETn,
  input  logic [7:0] PADDR,
  input  logic PSEL,
  input  logic PENABLE,
  input  logic PWRITE,
  input  logic [31:0] PWDATA,
  input  logic [3:0] PSTRB,
  input  logic [2:0] PPROT,
  // With RME, PNSE and PPROT[1] together name the Root PAS (AMBA APB5).
  input  logic PNSE,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,
  input  logic trafficQuiescent,
  output chi_cfg_pkg::chi_hnf_policy_t policy [NUM_HNF]
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam logic [7:0] ADDR_SELECT = 8'h00;
  localparam logic [7:0] ADDR_STAGED = 8'h04;
  localparam logic [7:0] ADDR_ACTIVE = 8'h08;
  localparam logic [7:0] ADDR_COMMIT = 8'h0c;
  localparam int unsigned SELECT_W = clog2Min1(NUM_HNF);
  localparam int unsigned POLICY_W = $bits(chi_hnf_policy_t);

  logic [SELECT_W-1:0] selected;
  chi_hnf_policy_t staged [NUM_HNF];
  logic transfer;
  logic addressImplemented;
  logic [31:0] strobedData;

  function automatic logic [31:0] mergeStrobes(
    input logic [31:0] oldValue,
    input logic [31:0] newValue,
    input logic [3:0] strobes
  );
    logic [31:0] value;
    value = oldValue;
    for (int unsigned byteLane = 0; byteLane < 4; byteLane++)
      if (strobes[byteLane])
        value[byteLane*8 +: 8] = newValue[byteLane*8 +: 8];
    return value;
  endfunction

  always_comb begin
    transfer = PSEL && PENABLE;
    PREADY = 1'b1;
    PRDATA = '0;
    addressImplemented = 1'b1;
    case (PADDR)
      ADDR_SELECT: PRDATA = 32'(selected);
      ADDR_STAGED: PRDATA = 32'(staged[selected]);
      ADDR_ACTIVE: PRDATA = 32'(policy[selected]);
      ADDR_COMMIT: PRDATA = '0;
      default: addressImplemented = 1'b0;
    endcase

    strobedData = mergeStrobes(PRDATA, PWDATA, PSTRB);
    PSLVERR = 1'b0;
    if (transfer) begin
      if ((PADDR[1:0] != 2'b00) || !addressImplemented)
        PSLVERR = 1'b1;
      else if (PWRITE && (PPROT[1] || (CFG.rmeEn && !PNSE)))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_ACTIVE))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_SELECT) && (strobedData >= NUM_HNF))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_COMMIT) && PSTRB[0] && PWDATA[0]
               && !trafficQuiescent)
        PSLVERR = 1'b1;
    end
  end

  always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
      selected <= '0;
      for (int unsigned hnf = 0; hnf < NUM_HNF; hnf++) begin
        staged[hnf] <= RESET_POLICY;
        policy[hnf] <= RESET_POLICY;
      end
    end else if (transfer && PWRITE && !PSLVERR) begin
      case (PADDR)
        ADDR_SELECT: selected <= strobedData[SELECT_W-1:0];
        ADDR_STAGED: staged[selected] <= chi_hnf_policy_t'(strobedData[POLICY_W-1:0]);
        ADDR_COMMIT:
          if (PSTRB[0] && PWDATA[0])
            for (int unsigned hnf = 0; hnf < NUM_HNF; hnf++)
              policy[hnf] <= staged[hnf];
        default: begin
        end
      endcase
    end
  end
endmodule
