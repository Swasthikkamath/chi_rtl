// Observability registers: RAS error records and interrupts, the HN-F
// performance counters and the crosspoint flit counters, one APB4 block of
// 256 bytes.
//
// RAS (with rasEn). There is one error record per HN-F and, when the GPC
// walks a table, one for the GPC after them. A record counts corrected and
// uncorrected errors (saturating) and keeps one error: the first
// uncorrected error since it was cleared or, while there is none, the most
// recent corrected error. An uncorrected error raises the record's
// interrupt, which stays HIGH until software clears the record.
//
// PMU (with pmuEn). Each HN-F has a 32-bit counter per event of
// chi_hnf_pkg::PMU_*, and each crosspoint a 32-bit count of the flits it took
// from and gave to its device ports, per channel. Counters wrap and run
// while PMU_CONTROL[0] is set.
//
// The register map and security rule are implementation defined; CHI
// defines no register interface. Writes need a Root access with RME
// (PNSE == 1, PPROT[1] == 0), or a Secure one as well when apbRootWrites is
// 0, and a Secure access without RME: the rule of the other blocks. Reads are
// unrestricted. A register of a feature that is not
// configured is not implemented and answers PSLVERR.
//
//   0x00 SELECT        RW  record or HN-F the next registers refer to
//   0x04 RAS_STATUS    RO  [0] uncorrected error recorded (the interrupt),
//                          [1] another uncorrected error since, [2] the
//                          recorded error is corrected, [7:4] its source
//                          (chi_hnf_pkg::RAS_SRC_*)
//   0x08 RAS_CE_COUNT  RO  corrected errors
//   0x0C RAS_UE_COUNT  RO  uncorrected errors
//   0x10 RAS_ADDR_LO   RO  address [31:0] of the recorded error
//   0x14 RAS_ADDR_HI   RO  [19:0] address [51:32], [26:24] its PAS
//   0x18 RAS_CLEAR     WO  PWDATA[0] clears the record and its interrupt,
//                          PWDATA[1] zeroes both counts
//   0x20 PMU_CONTROL   RW  [0] counters run; writing PWDATA[1] = 1 zeroes
//                          every counter
//   0x40 + 4n PMU_EVENT RO counter n of the selected HN-F, n = 0 to 15
//   0x80 XP_SELECT     RW  [7:0] crosspoint, [9:8] channel (REQ, RSP, SNP,
//                          DAT), [10] 0 flits taken in, 1 flits given out
//   0x84 XP_FLITS      RO  the selected count
module chi_obs_regs #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_HNF = (CFG.numHnf > 0) ? CFG.numHnf : 1,
  // Error records: one per HN-F, then the GPC's when it walks a table.
  parameter int unsigned NUM_REC = NUM_HNF,
  parameter int unsigned NUM_XP = 1
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
  input  logic [NUM_REC-1:0] rasCorrected,
  input  logic [NUM_REC-1:0] rasUncorrected,
  input  logic [NUM_REC-1:0][3:0] rasSource,
  input  logic [NUM_REC-1:0][chi_pkg::CHI_MAX_ADDR_W-1:0] rasAddr,
  input  logic [NUM_REC-1:0][2:0] rasPas,   // chi_pkg::chi_pas_e
  output logic [NUM_REC-1:0] rasIrq,
  input  logic [NUM_HNF-1:0][chi_hnf_pkg::HNF_PMU_EVENTS-1:0][7:0] pmuCount,
  input  logic [NUM_XP-1:0][3:0][3:0] xpInjected,
  input  logic [NUM_XP-1:0][3:0][3:0] xpEjected
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  localparam logic [7:0] ADDR_SELECT = 8'h00;
  localparam logic [7:0] ADDR_RAS_STATUS = 8'h04;
  localparam logic [7:0] ADDR_RAS_CE_COUNT = 8'h08;
  localparam logic [7:0] ADDR_RAS_UE_COUNT = 8'h0c;
  localparam logic [7:0] ADDR_RAS_ADDR_LO = 8'h10;
  localparam logic [7:0] ADDR_RAS_ADDR_HI = 8'h14;
  localparam logic [7:0] ADDR_RAS_CLEAR = 8'h18;
  localparam logic [7:0] ADDR_PMU_CONTROL = 8'h20;
  localparam logic [7:0] ADDR_PMU_EVENT = 8'h40;
  localparam logic [7:0] ADDR_XP_SELECT = 8'h80;
  localparam logic [7:0] ADDR_XP_FLITS = 8'h84;
  localparam int unsigned SELECT_W = clog2Min1(NUM_REC);
  localparam int unsigned XP_W = clog2Min1(NUM_XP);

  // Error records.
  logic [NUM_REC-1:0] ueValid;
  logic [NUM_REC-1:0] ueOverflow;
  logic [NUM_REC-1:0] ceRecorded;
  logic [NUM_REC-1:0][3:0] recSource;
  logic [NUM_REC-1:0][CHI_MAX_ADDR_W-1:0] recAddr;
  logic [NUM_REC-1:0][2:0] recPas;
  logic [NUM_REC-1:0][31:0] ceCount;
  logic [NUM_REC-1:0][31:0] ueCount;
  // Counters.
  logic pmuRun;
  logic [NUM_HNF-1:0][HNF_PMU_EVENTS-1:0][31:0] eventCount;
  logic [NUM_XP-1:0][1:0][3:0][31:0] xpCount;

  logic [SELECT_W-1:0] selected;
  logic [XP_W-1:0] xpSelected;
  logic [1:0] xpChannel;
  logic xpGiven;
  logic transfer;
  logic addressImplemented;
  logic [31:0] strobedData;
  logic writeOk;
  logic rasClear;
  logic rasZero;
  logic pmuZero;

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

  function automatic logic [31:0] saturatingAdd(input logic [31:0] value);
    return (value == '1) ? value : (value + 32'd1);
  endfunction

  always_comb begin
    logic [CHI_MAX_ADDR_W-1:0] address;
    transfer = PSEL && PENABLE;
    PREADY = 1'b1;
    PRDATA = '0;
    addressImplemented = 1'b1;
    address = recAddr[selected];
    if (PADDR == ADDR_SELECT)
      PRDATA = 32'(selected);
    else if (CFG.rasEn && (PADDR == ADDR_RAS_STATUS))
      PRDATA = {24'd0, recSource[selected], 1'b0, ceRecorded[selected] && !ueValid[selected],
                ueOverflow[selected], ueValid[selected]};
    else if (CFG.rasEn && (PADDR == ADDR_RAS_CE_COUNT))
      PRDATA = ceCount[selected];
    else if (CFG.rasEn && (PADDR == ADDR_RAS_UE_COUNT))
      PRDATA = ueCount[selected];
    else if (CFG.rasEn && (PADDR == ADDR_RAS_ADDR_LO))
      PRDATA = address[31:0];
    else if (CFG.rasEn && (PADDR == ADDR_RAS_ADDR_HI))
      PRDATA = {5'd0, recPas[selected], 4'd0, 20'(address >> 32)};
    else if (CFG.rasEn && (PADDR == ADDR_RAS_CLEAR))
      PRDATA = '0;
    else if (CFG.pmuEn && (PADDR == ADDR_PMU_CONTROL))
      PRDATA = 32'(pmuRun);
    else if (CFG.pmuEn && (PADDR >= ADDR_PMU_EVENT)
             && (PADDR < (ADDR_PMU_EVENT + 8'(4 * HNF_PMU_EVENTS))))
      PRDATA = (int'(selected) < NUM_HNF)
               ? eventCount[int'(selected)][(int'(PADDR) - int'(ADDR_PMU_EVENT)) / 4]
               : '0;
    else if (CFG.pmuEn && (PADDR == ADDR_XP_SELECT))
      PRDATA = {21'd0, xpGiven, xpChannel, 8'(xpSelected)};
    else if (CFG.pmuEn && (PADDR == ADDR_XP_FLITS))
      PRDATA = xpCount[xpSelected][xpGiven][xpChannel];
    else
      addressImplemented = 1'b0;

    strobedData = mergeStrobes(PRDATA, PWDATA, PSTRB);
    writeOk = transfer && PWRITE;
    PSLVERR = 1'b0;
    if (transfer) begin
      if ((PADDR[1:0] != 2'b00) || !addressImplemented)
        PSLVERR = 1'b1;
      else if (PWRITE && (PPROT[1] || (CFG.rmeEn && CFG.apbRootWrites && !PNSE)))
        PSLVERR = 1'b1;
      else if (PWRITE && !((PADDR == ADDR_SELECT) || (PADDR == ADDR_RAS_CLEAR)
                           || (PADDR == ADDR_PMU_CONTROL)
                           || (PADDR == ADDR_XP_SELECT)))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_SELECT) && (strobedData >= NUM_REC))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_XP_SELECT)
               && ((strobedData[7:0] >= NUM_XP) || (strobedData[31:11] != '0)))
        PSLVERR = 1'b1;
    end
    writeOk = writeOk && !PSLVERR;
    rasClear = writeOk && (PADDR == ADDR_RAS_CLEAR) && PSTRB[0] && PWDATA[0];
    rasZero = writeOk && (PADDR == ADDR_RAS_CLEAR) && PSTRB[0] && PWDATA[1];
    pmuZero = writeOk && (PADDR == ADDR_PMU_CONTROL) && PSTRB[0] && PWDATA[1];
  end

  always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
      selected <= '0;
      xpSelected <= '0;
      xpChannel <= '0;
      xpGiven <= 1'b0;
      pmuRun <= 1'b0;
    end else if (writeOk) begin
      case (PADDR)
        ADDR_SELECT: selected <= strobedData[SELECT_W-1:0];
        ADDR_PMU_CONTROL: pmuRun <= strobedData[0];
        ADDR_XP_SELECT: begin
          xpSelected <= strobedData[XP_W-1:0];
          xpChannel <= strobedData[9:8];
          xpGiven <= strobedData[10];
        end
        default: begin
        end
      endcase
    end
  end

  // Error records. A clear and a new error in one cycle leave the new error.
  always_ff @(posedge PCLK) begin
    if (!PRESETn || !CFG.rasEn) begin
      ueValid <= '0;
      ueOverflow <= '0;
      ceRecorded <= '0;
      recSource <= '0;
      recAddr <= '0;
      recPas <= '0;
      ceCount <= '0;
      ueCount <= '0;
    end else begin
      for (int unsigned r = 0; r < NUM_REC; r++) begin
        logic clearThis;
        clearThis = rasClear && (int'(selected) == r);
        if (clearThis) begin
          ueValid[r] <= 1'b0;
          ueOverflow[r] <= 1'b0;
          ceRecorded[r] <= 1'b0;
        end
        if (rasZero && (int'(selected) == r)) begin
          ceCount[r] <= '0;
          ueCount[r] <= '0;
        end else begin
          if (rasCorrected[r])
            ceCount[r] <= saturatingAdd(ceCount[r]);
          if (rasUncorrected[r])
            ueCount[r] <= saturatingAdd(ueCount[r]);
        end
        if (rasUncorrected[r]) begin
          if (ueValid[r] && !clearThis) begin
            ueOverflow[r] <= 1'b1;
          end else begin
            ueValid[r] <= 1'b1;
            ceRecorded[r] <= 1'b0;
            recSource[r] <= rasSource[r];
            recAddr[r] <= rasAddr[r];
            recPas[r] <= rasPas[r];
          end
        end else if (rasCorrected[r] && (!ueValid[r] || clearThis)) begin
          ceRecorded[r] <= 1'b1;
          recSource[r] <= rasSource[r];
          recAddr[r] <= rasAddr[r];
          recPas[r] <= rasPas[r];
        end
      end
    end
  end

  always_comb
    rasIrq = CFG.rasEn ? ueValid : '0;

  // Counters.
  always_ff @(posedge PCLK) begin
    if (!PRESETn || !CFG.pmuEn) begin
      eventCount <= '0;
      xpCount <= '0;
    end else if (pmuZero) begin
      eventCount <= '0;
      xpCount <= '0;
    end else if (pmuRun) begin
      for (int unsigned h = 0; h < NUM_HNF; h++)
        for (int unsigned e = 0; e < HNF_PMU_EVENTS; e++)
          eventCount[h][e] <= eventCount[h][e] + 32'(pmuCount[h][e]);
      for (int unsigned x = 0; x < NUM_XP; x++)
        for (int unsigned c = 0; c < 4; c++) begin
          xpCount[x][0][c] <= xpCount[x][0][c] + 32'(xpInjected[x][c]);
          xpCount[x][1][c] <= xpCount[x][1][c] + 32'(xpEjected[x][c]);
        end
    end
  end
endmodule
