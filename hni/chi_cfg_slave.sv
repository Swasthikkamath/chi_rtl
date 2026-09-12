module chi_cfg_slave #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_REGIONS = 4,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.nodeIdW-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [3:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0}
) (
  input  logic PCLK,
  input  logic PRESETn,
  input  logic [11:0] PADDR,
  input  logic PSEL,
  input  logic PENABLE,
  input  logic PWRITE,
  input  logic [31:0] PWDATA,
  input  logic [3:0] PSTRB,
  input  logic [2:0] PPROT,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,

  input  logic trafficQuiescent,
  output logic regionUpdate,
  output logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  output logic [CFG.addrW-1:0] regionUpdateBase,
  output logic [CFG.addrW-1:0] regionUpdateLimit,
  output logic [CFG.nodeIdW-1:0] regionUpdateTarget,
  output logic [3:0] regionUpdateAttributes
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam logic [11:0] ADDR_SELECT     = 12'h000;
  localparam logic [11:0] ADDR_BASE_LO    = 12'h004;
  localparam logic [11:0] ADDR_BASE_HI    = 12'h008;
  localparam logic [11:0] ADDR_LIMIT_LO   = 12'h00c;
  localparam logic [11:0] ADDR_LIMIT_HI   = 12'h010;
  localparam logic [11:0] ADDR_TARGET     = 12'h014;
  localparam logic [11:0] ADDR_ATTRIBUTES = 12'h018;
  localparam logic [11:0] ADDR_COMMIT     = 12'h01c;

  logic [clog2Min1(NUM_REGIONS)-1:0] selectedRegion;
  logic [CFG.addrW-1:0] stagedBase [NUM_REGIONS-1:0];
  logic [CFG.addrW-1:0] stagedLimit [NUM_REGIONS-1:0];
  logic [CFG.nodeIdW-1:0] stagedTarget [NUM_REGIONS-1:0];
  logic [3:0] stagedAttributes [NUM_REGIONS-1:0];
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
      ADDR_SELECT:
        PRDATA = {{(32-clog2Min1(NUM_REGIONS)){1'b0}}, selectedRegion};
      ADDR_BASE_LO:
        PRDATA = stagedBase[selectedRegion][31:0];
      ADDR_BASE_HI:
        PRDATA = 32'(stagedBase[selectedRegion] >> 32);
      ADDR_LIMIT_LO:
        PRDATA = stagedLimit[selectedRegion][31:0];
      ADDR_LIMIT_HI:
        PRDATA = 32'(stagedLimit[selectedRegion] >> 32);
      ADDR_TARGET:
        PRDATA = {{(32-CFG.nodeIdW){1'b0}}, stagedTarget[selectedRegion]};
      ADDR_ATTRIBUTES:
        PRDATA = {28'b0, stagedAttributes[selectedRegion]};
      ADDR_COMMIT:
        PRDATA = '0;
      default:
        addressImplemented = 1'b0;
    endcase

    strobedData = mergeStrobes(PRDATA, PWDATA, PSTRB);
    PSLVERR = 1'b0;
    if (transfer) begin
      if (CFG.cfgAccess != CFG_APB)
        PSLVERR = 1'b1;
      else if (PADDR[1:0] != 2'b00 || !addressImplemented)
        PSLVERR = 1'b1;
      // This implementation defines all configuration writes as secure control.
      else if (PWRITE && PPROT[1])
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_SELECT)
               && (strobedData >= NUM_REGIONS))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_COMMIT) && PSTRB[0]
               && !trafficQuiescent)
        PSLVERR = 1'b1;
    end
  end

  always_ff @(posedge PCLK) begin
    if (!PRESETn) begin
      selectedRegion <= '0;
      regionUpdate <= 1'b0;
      regionUpdateIndex <= '0;
      regionUpdateBase <= '0;
      regionUpdateLimit <= '0;
      regionUpdateTarget <= '0;
      regionUpdateAttributes <= '0;
      for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
        stagedBase[region] <= REGION_BASE[region];
        stagedLimit[region] <= REGION_LIMIT[region];
        stagedTarget[region] <= REGION_TARGET[region];
        stagedAttributes[region] <= REGION_ATTRIBUTES[region];
      end
    end else begin
      regionUpdate <= 1'b0;
      if (transfer && PWRITE && !PSLVERR) begin
        case (PADDR)
          ADDR_SELECT:
            selectedRegion <= strobedData[clog2Min1(NUM_REGIONS)-1:0];
          ADDR_BASE_LO:
            stagedBase[selectedRegion][31:0] <= strobedData;
          ADDR_BASE_HI:
            stagedBase[selectedRegion][CFG.addrW-1:32] <=
              strobedData[CFG.addrW-33:0];
          ADDR_LIMIT_LO:
            stagedLimit[selectedRegion][31:0] <= strobedData;
          ADDR_LIMIT_HI:
            stagedLimit[selectedRegion][CFG.addrW-1:32] <=
              strobedData[CFG.addrW-33:0];
          ADDR_TARGET:
            stagedTarget[selectedRegion] <= strobedData[CFG.nodeIdW-1:0];
          ADDR_ATTRIBUTES:
            stagedAttributes[selectedRegion] <= strobedData[3:0];
          ADDR_COMMIT:
            if (PSTRB[0]) begin
              regionUpdate <= 1'b1;
              regionUpdateIndex <= selectedRegion;
              regionUpdateBase <= stagedBase[selectedRegion];
              regionUpdateLimit <= stagedLimit[selectedRegion];
              regionUpdateTarget <= stagedTarget[selectedRegion];
              regionUpdateAttributes <= stagedAttributes[selectedRegion];
            end
          default: begin
          end
        endcase
      end
    end
  end
endmodule
