// QoS regulator registers, one APB4 block of 256 bytes (block 4), present
// with qosRegEn and APB configuration.
//
// The register map and security rule are implementation defined; CHI
// defines no register interface. Writes follow the rule of the other blocks:
// Root with RME (Secure as well when apbRootWrites is 0) and Secure without
// it. Reads are unrestricted. A value out of range returns PSLVERR and
// changes nothing; a new rate or burst applies from the next cycle.
//
//   0x00 SELECT  RW  Request Node port (ordinal) the next registers refer to
//   0x04 RATE    RW  tokens added to its bucket per 256 cycles, 1 to 256
//   0x08 BURST   RW  tokens its bucket holds, 1 to 255
//   0x0C TOKENS  RO  tokens in its bucket now
module chi_qos_regs #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1
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
  input  logic PNSE,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,
  input  logic [NUM_PORTS-1:0][7:0] tokens,
  output logic [NUM_PORTS-1:0][8:0] rate,
  output logic [NUM_PORTS-1:0][7:0] burst
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam logic [7:0] ADDR_SELECT = 8'h00;
  localparam logic [7:0] ADDR_RATE = 8'h04;
  localparam logic [7:0] ADDR_BURST = 8'h08;
  localparam logic [7:0] ADDR_TOKENS = 8'h0c;
  localparam int unsigned SELECT_W = clog2Min1(NUM_PORTS);
  localparam logic [8:0] RESET_RATE = (CFG.qosRegRate > 256) ? 9'd256
                                      : ((CFG.qosRegRate == 0) ? 9'd1 : 9'(CFG.qosRegRate));
  localparam logic [7:0] RESET_BURST = (CFG.qosRegBurst > 255) ? 8'd255
                                       : ((CFG.qosRegBurst == 0) ? 8'd1 : 8'(CFG.qosRegBurst));

  logic [SELECT_W-1:0] selected;
  logic transfer;
  logic addressImplemented;
  logic [31:0] strobedData;
  logic writeOk;

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
      ADDR_RATE:   PRDATA = 32'(rate[selected]);
      ADDR_BURST:  PRDATA = 32'(burst[selected]);
      ADDR_TOKENS: PRDATA = 32'(tokens[selected]);
      default:     addressImplemented = 1'b0;
    endcase

    strobedData = mergeStrobes(PRDATA, PWDATA, PSTRB);
    PSLVERR = 1'b0;
    if (transfer) begin
      if ((PADDR[1:0] != 2'b00) || !addressImplemented)
        PSLVERR = 1'b1;
      else if (PWRITE && (PPROT[1] || (CFG.rmeEn && CFG.apbRootWrites && !PNSE)))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_TOKENS))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_SELECT) && (strobedData >= NUM_PORTS))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_RATE)
               && ((strobedData == '0) || (strobedData > 32'd256)))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_BURST)
               && ((strobedData == '0) || (strobedData > 32'd255)))
        PSLVERR = 1'b1;
    end
    writeOk = transfer && PWRITE && !PSLVERR;
  end

  always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
      selected <= '0;
      for (int unsigned p = 0; p < NUM_PORTS; p++) begin
        rate[p] <= RESET_RATE;
        burst[p] <= RESET_BURST;
      end
    end else if (writeOk) begin
      case (PADDR)
        ADDR_SELECT: selected <= strobedData[SELECT_W-1:0];
        ADDR_RATE:   rate[selected] <= strobedData[8:0];
        ADDR_BURST:  burst[selected] <= strobedData[7:0];
        default: begin
        end
      endcase
    end
  end
endmodule
