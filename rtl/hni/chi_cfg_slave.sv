// Region editor, APB4 block 0: stages a SAM region and commits it.
//
// SELECT names a region; BASE, LIMIT, TARGET and ATTRIBUTES stage its fields;
// COMMIT copies the staged region into the SAM. A commit is taken only while
// traffic is quiescent and only for a legal region: whole 64-byte lines with
// base at or below limit, a defined kind, only PASs the configuration
// defines, and for a DIRECT or MMIO region a Home that exists (an HN-I for
// MMIO). A refused commit returns PSLVERR and changes nothing. Writes need
// the Root PAS with RME (Secure as well when apbRootWrites is 0) and the
// Secure PAS without it; reads are unrestricted.
module chi_cfg_slave #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_REGIONS = 4,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0},
  // The Homes a region may target: a DIRECT region any of them, an MMIO
  // region an HN-I.
  parameter int unsigned NUM_HNF_IDS = 1,
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    HNF_IDS [NUM_HNF_IDS] = '{default:'0},
  parameter int unsigned NUM_HNI_IDS = 1,
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    HNI_IDS [NUM_HNI_IDS] = '{default:'0},
  parameter bit HNF_PRESENT = 1'b1,
  parameter bit HNI_PRESENT = 1'b1
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
  // With RME, PNSE and PPROT[1] together name the Root PAS (AMBA APB5).
  input  logic PNSE,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,

  input  logic trafficQuiescent,
  output logic regionUpdate,
  output logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  output logic [CFG.addrW-1:0] regionUpdateBase,
  output logic [CFG.addrW-1:0] regionUpdateLimit,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget,
  output logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] regionUpdateAttributes
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
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] stagedTarget [NUM_REGIONS-1:0];
  logic [CHI_SAM_ATTR_W-1:0] stagedAttributes [NUM_REGIONS-1:0];
  logic transfer;
  logic addressImplemented;
  logic [31:0] strobedData;
  logic commitLegal;

  // A region is committed only when it is legal (chi_pkg::samRegionLegal) and
  // a DIRECT or MMIO region names a Home that exists.
  function automatic logic targetLegal(
    input logic [CHI_SAM_ATTR_W-1:0] attributes,
    input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] target
  );
    logic isHnf;
    logic isHni;
    isHnf = 1'b0;
    isHni = 1'b0;
    for (int unsigned i = 0; i < NUM_HNF_IDS; i++)
      if (HNF_PRESENT && (target == HNF_IDS[i]))
        isHnf = 1'b1;
    for (int unsigned i = 0; i < NUM_HNI_IDS; i++)
      if (HNI_PRESENT && (target == HNI_IDS[i]))
        isHni = 1'b1;
    if (!attributes[0])
      return 1'b1;
    case (attributes[3:2])
      SAM_REGION_DIRECT: return isHnf || isHni;
      SAM_REGION_MMIO:   return isHni;
      default:           return 1'b1;
    endcase
  endfunction

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
        PRDATA = {{(32 - chi_cfg_pkg::CHI_NODEID_SLOT_W){1'b0}},
                  stagedTarget[selectedRegion]};
      ADDR_ATTRIBUTES:
        PRDATA = 32'(stagedAttributes[selectedRegion]);
      ADDR_COMMIT:
        PRDATA = '0;
      default:
        addressImplemented = 1'b0;
    endcase

    strobedData = mergeStrobes(PRDATA, PWDATA, PSTRB);
    commitLegal = samRegionLegal(CFG, CHI_MAX_ADDR_W'(stagedBase[selectedRegion]),
                                 CHI_MAX_ADDR_W'(stagedLimit[selectedRegion]),
                                 stagedAttributes[selectedRegion])
                  && targetLegal(stagedAttributes[selectedRegion],
                                 stagedTarget[selectedRegion]);
    PSLVERR = 1'b0;
    if (transfer) begin
      if (CFG.cfgAccess != CFG_APB)
        PSLVERR = 1'b1;
      else if (PADDR[1:0] != 2'b00 || !addressImplemented)
        PSLVERR = 1'b1;
      // Configuration writes are Root control with RME and Secure control
      // without it, the same qualification the CHI MMIO window applies.
      else if (PWRITE && (PPROT[1] || (CFG.rmeEn && CFG.apbRootWrites && !PNSE)))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_SELECT)
               && (strobedData >= NUM_REGIONS))
        PSLVERR = 1'b1;
      else if (PWRITE && (PADDR == ADDR_COMMIT) && PSTRB[0]
               && (!trafficQuiescent || !commitLegal))
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
            stagedTarget[selectedRegion] <= strobedData[chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0];
          ADDR_ATTRIBUTES:
            stagedAttributes[selectedRegion] <= strobedData[CHI_SAM_ATTR_W-1:0];
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
