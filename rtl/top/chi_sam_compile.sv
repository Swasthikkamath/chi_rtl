module chi_sam_compile (
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
  output logic PSLVERR
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_REGIONS = 4;
  localparam int unsigned NUM_HNF = CHI_CFG_DEFAULT.numHnf;

  function automatic chi_cfg_t makeApbCfg(input chi_cfg_t cfg);
    chi_cfg_t value;
    value = cfg;
    value.cfgAccess = CFG_APB;
    return value;
  endfunction

  localparam chi_cfg_t APB_CFG = makeApbCfg(CHI_CFG_DEFAULT);
  // These are explicit integration NodeIDs, encoded by the common CHI helper.
  localparam logic [CHI_MAX_NODEID_W-1:0] HN_NODE_IDS [NUM_HNF-1:0] = '{
    encodeNodeId(CHI_CFG_DEFAULT, 2, 2, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 2, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 2, 0, 0, 0),
    encodeNodeId(CHI_CFG_DEFAULT, 0, 0, 0, 0)
  };
  localparam logic [APB_CFG.addrW-1:0] REGION_BASE [NUM_REGIONS-1:0] =
    '{48'h0000_0000_0000, 48'h0000_0000_0000,
      48'h0000_0000_0000, 48'h0000_0000_0000};
  localparam logic [APB_CFG.addrW-1:0] REGION_LIMIT [NUM_REGIONS-1:0] =
    '{48'hffff_ffff_ffff, 48'h0000_0000_0000,
      48'h0000_0000_0000, 48'h0000_0000_0000};
  localparam logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] REGION_TARGET [NUM_REGIONS-1:0] =
    '{default:'0};
  localparam logic [CHI_SAM_ATTR_W-1:0] REGION_ATTRIBUTES [NUM_REGIONS-1:0] =
    '{samAttributes(SAM_REGION_HNF_HASH, 8'hff, 1'b1), '0, '0, '0};

  logic regionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex;
  logic [APB_CFG.addrW-1:0] regionUpdateBase;
  logic [APB_CFG.addrW-1:0] regionUpdateLimit;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget;
  logic [CHI_SAM_ATTR_W-1:0] regionUpdateAttributes;
  logic [APB_CFG.addrW-1:0] sampleAddress;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requesterTarget;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] subordinateTarget;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] defaultHashTarget;
  logic [CHI_SAM_ATTR_W-1:0] requesterAttributes;
  logic [CHI_SAM_ATTR_W-1:0] subordinateAttributes;
  logic requesterUnmapped;
  logic subordinateUnmapped;
  logic requesterPasError;
  logic subordinatePasError;

  assign sampleAddress = '0;

  chi_hn_hash #(
    .CFG(APB_CFG),
    .NUM_HNF(NUM_HNF),
    .HN_NODE_IDS(HN_NODE_IDS)
  ) default_hash (
    .address(sampleAddress),
    .targetNodeId(defaultHashTarget)
  );

  chi_sam #(
    .CFG(APB_CFG),
    .NUM_REGIONS(NUM_REGIONS),
    .HASH_TO_HNF(1'b1),
    .NUM_HNF(NUM_HNF),
    .HN_NODE_IDS(HN_NODE_IDS),
    .REGION_BASE(REGION_BASE),
    .REGION_LIMIT(REGION_LIMIT),
    .REGION_TARGET(REGION_TARGET),
    .REGION_ATTRIBUTES(REGION_ATTRIBUTES)
  ) requester_sam (
    .clk(PCLK),
    .resetn(PRESETn),
    .address(sampleAddress),
    .pas(PAS_SECURE),
    .targetNodeId(requesterTarget),
    .matchedAttributes(requesterAttributes),
    .unmappedError(requesterUnmapped),
    .pasError(requesterPasError),
    .regionUpdate(regionUpdate),
    .regionUpdateIndex(regionUpdateIndex),
    .regionUpdateBase(regionUpdateBase),
    .regionUpdateLimit(regionUpdateLimit),
    .regionUpdateTarget(regionUpdateTarget),
    .regionUpdateAttributes(regionUpdateAttributes)
  );

  // The same table module serves the second HN-address-to-SN lookup level.
  chi_sam #(
    .CFG(APB_CFG),
    .NUM_REGIONS(NUM_REGIONS),
    .HASH_TO_HNF(1'b0),
    .NUM_HNF(NUM_HNF),
    .HN_NODE_IDS(HN_NODE_IDS),
    .REGION_BASE(REGION_BASE),
    .REGION_LIMIT(REGION_LIMIT),
    .REGION_TARGET(REGION_TARGET),
    .REGION_ATTRIBUTES(REGION_ATTRIBUTES)
  ) subordinate_sam (
    .clk(PCLK),
    .resetn(PRESETn),
    .address(sampleAddress),
    .pas(PAS_SECURE),
    .targetNodeId(subordinateTarget),
    .matchedAttributes(subordinateAttributes),
    .unmappedError(subordinateUnmapped),
    .pasError(subordinatePasError),
    .regionUpdate(1'b0),
    .regionUpdateIndex('0),
    .regionUpdateBase('0),
    .regionUpdateLimit('0),
    .regionUpdateTarget('0),
    .regionUpdateAttributes('0)
  );

  chi_cfg_slave #(
    .CFG(APB_CFG),
    .NUM_REGIONS(NUM_REGIONS),
    .REGION_BASE(REGION_BASE),
    .REGION_LIMIT(REGION_LIMIT),
    .REGION_TARGET(REGION_TARGET),
    .REGION_ATTRIBUTES(REGION_ATTRIBUTES)
  ) cfg_slave (
    .PCLK(PCLK),
    .PRESETn(PRESETn),
    .PADDR(PADDR),
    .PSEL(PSEL),
    .PENABLE(PENABLE),
    .PWRITE(PWRITE),
    .PWDATA(PWDATA),
    .PSTRB(PSTRB),
    .PPROT(PPROT),
    .PNSE(1'b1),
    .PRDATA(PRDATA),
    .PREADY(PREADY),
    .PSLVERR(PSLVERR),
    .trafficQuiescent(1'b1),
    .regionUpdate(regionUpdate),
    .regionUpdateIndex(regionUpdateIndex),
    .regionUpdateBase(regionUpdateBase),
    .regionUpdateLimit(regionUpdateLimit),
    .regionUpdateTarget(regionUpdateTarget),
    .regionUpdateAttributes(regionUpdateAttributes)
  );

  generate
    begin : chi_cfg_check
      initial begin
        if (NUM_REGIONS == 0)
          $fatal(1, "SAM requires at least one region");
        if (NUM_HNF == 0)
          $fatal(1, "HN hashing requires at least one HN-F");
        if ((APB_CFG.interleaveGranule == 0)
            || ((APB_CFG.interleaveGranule
                 & (APB_CFG.interleaveGranule - 1)) != 0))
          $fatal(1, "HN interleave granule must be a power of two");
        if ((APB_CFG.hnHashShift == 0)
            || (APB_CFG.hnHashShift >= APB_CFG.addrW))
          $fatal(1, "HN hash shift must be within the address width");
        for (int unsigned region = 0; region < NUM_REGIONS; region++)
          if (REGION_ATTRIBUTES[region][0]
              && (REGION_BASE[region] > REGION_LIMIT[region]))
            $fatal(1, "Valid SAM region has base above limit");
      end
    end
  endgenerate
endmodule
