// Granule Protection Check unit, shared by every Home.
//
// Each Home asks, for every request it admits, whether the request's PAS may
// access its physical granule; a request that may not is completed by the
// Home with NDERR and has no other effect (IHI 0050H B9.1.1). The check is
// made before the Home snoops, looks up its SLC or sends anything
// downstream.
//
// gpcMode TABLE  a GPI per granule in an on-chip array covering
//                gpcTableGranules granules from a programmable base; an
//                address outside that range is not protected. The array
//                resets to RESET_GPI and is written by Root only.
// gpcMode WALK   the Granule Protection Table in memory, decoded per the RME
//                chapter of the Arm ARM: a level 0 entry per L0GPTSZ region,
//                either a block descriptor carrying one GPI (type 0b0001) or
//                a table descriptor (type 0b0011) pointing at level 1
//                entries of sixteen 4-bit GPIs. A walk reads each line
//                through the HN-F that owns it, using a downstream tracker
//                reserved for the walker in that HN-F, in the Root PAS.
//                Results are kept in a gpcCacheEntries cache; a descriptor
//                that is neither type, or a read that fails, caches a fault.
//
// The answer for an address the cache or table holds is combinational, so a
// Home admits most requests already checked. A miss leaves the request
// waiting at its Home, which presents it again until the walk has filled
// the cache.
//
// Registers (APB block 2; writes need the Root PAS, reads are open):
//   0x00 CTRL         [0] enable, [2:1] PGS (granule 4K/64K/16K),
//                     [6:4] PPS, [11:8] L0GPTSZ
//   0x04/0x08 TABLE_BASE  first byte of the TABLE range (granule aligned)
//   0x0C/0x10 GPT_BASE    level 0 table base (WALK, 4 KB aligned)
//   0x14 GPI_INDEX    granule index into the TABLE array
//   0x18 GPI_DATA     eight GPIs for granules GPI_INDEX & ~7 onwards
//   0x1C INVALIDATE   write [0] invalidate the GPT cache, [1] invalidate the
//                     entries holding INV_ADDR
//   0x20/0x24 INV_ADDR
//   0x28 FAULT_STATUS [0] a fault is recorded (write 1 to clear),
//                     [31:16] faults counted, saturating
//   0x2C/0x30 FAULT_ADDR  physical address of the first recorded fault
//   0x34 FAULT_INFO   [2:0] PAS, [3] malformed GPT, [26:16] SrcID
//   0x38 STATUS       [0] a walk is in progress
// Writing CTRL or GPT_BASE invalidates the GPT cache.
module chi_gpc #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  // Homes in order: every HN-F, then every HN-I.
  parameter int unsigned NUM_HOMES = 1,
  parameter int unsigned NUM_HNF = 1,
  parameter logic [3:0] RESET_GPI = 4'b1111,
  parameter bit RESET_ENABLE = 1'b0
) (
  input  logic clk,
  input  logic resetn,
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
  input  logic [NUM_HOMES-1:0] checkValid,
  input  logic [NUM_HOMES-1:0][chi_pkg::CHI_MAX_ADDR_W-1:0] checkAddr,
  input  chi_pkg::chi_pas_e [NUM_HOMES-1:0] checkPas,
  input  logic [NUM_HOMES-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] checkSrcId,
  output logic [NUM_HOMES-1:0] checkDone,
  output logic [NUM_HOMES-1:0] checkFail,
  output logic [NUM_HNF-1:0] gptReadValid,
  output logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gptReadAddr,
  input  logic [NUM_HNF-1:0] gptReadDone,
  input  logic [NUM_HNF-1:0][511:0] gptReadData,
  input  logic [NUM_HNF-1:0] gptReadError,
  // GPT cache invalidation carried by DVM.
  input  logic dvmInvalidateAll,
  input  logic dvmInvalidateByPa,
  input  logic [chi_pkg::CHI_MAX_ADDR_W-1:0] dvmInvalidateAddr,
  output logic walking,
  output logic eventFault
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned ADDR_W = CHI_MAX_ADDR_W;
  localparam int unsigned GRANULES = (CFG.gpcTableGranules > 0) ? CFG.gpcTableGranules : 1;
  localparam int unsigned GIDX_W = clog2Min1(GRANULES);
  localparam int unsigned ENTRIES = (CFG.gpcCacheEntries > 0) ? CFG.gpcCacheEntries : 1;
  localparam int unsigned EIDX_W = clog2Min1(ENTRIES);
  localparam int unsigned HOME_W = clog2Min1(NUM_HOMES);
  localparam int unsigned HNF_W = clog2Min1(NUM_HNF);

  localparam logic [7:0] ADDR_CTRL          = 8'h00;
  localparam logic [7:0] ADDR_TABLE_BASE_LO = 8'h04;
  localparam logic [7:0] ADDR_TABLE_BASE_HI = 8'h08;
  localparam logic [7:0] ADDR_GPT_BASE_LO   = 8'h0c;
  localparam logic [7:0] ADDR_GPT_BASE_HI   = 8'h10;
  localparam logic [7:0] ADDR_GPI_INDEX     = 8'h14;
  localparam logic [7:0] ADDR_GPI_DATA      = 8'h18;
  localparam logic [7:0] ADDR_INVALIDATE    = 8'h1c;
  localparam logic [7:0] ADDR_INV_ADDR_LO   = 8'h20;
  localparam logic [7:0] ADDR_INV_ADDR_HI   = 8'h24;
  localparam logic [7:0] ADDR_FAULT_STATUS  = 8'h28;
  localparam logic [7:0] ADDR_FAULT_ADDR_LO = 8'h2c;
  localparam logic [7:0] ADDR_FAULT_ADDR_HI = 8'h30;
  localparam logic [7:0] ADDR_FAULT_INFO    = 8'h34;
  localparam logic [7:0] ADDR_STATUS        = 8'h38;

  // Configuration.
  logic enable;
  logic [1:0] pgs;
  logic [2:0] pps;
  logic [3:0] l0gptsz;
  logic [ADDR_W-1:0] tableBase;
  logic [ADDR_W-1:0] gptBase;
  logic [GIDX_W-1:0] gpiIndex;
  logic [ADDR_W-1:0] invAddr;
  logic [3:0] gpiTable [GRANULES];

  // Fault record.
  logic faultValid;
  logic [15:0] faultCount;
  logic [ADDR_W-1:0] faultAddr;
  chi_pas_e faultPas;
  logic faultMalformed;
  logic [CHI_NODEID_SLOT_W-1:0] faultSrcId;

  // GPT cache: an entry holds a level 0 block GPI or a level 1 descriptor,
  // or records that the GPT faulted for that region.
  logic [ENTRIES-1:0] cacheValid;
  logic [ENTRIES-1:0] cacheLevel1;
  logic [ENTRIES-1:0] cacheFault;
  logic [ENTRIES-1:0][ADDR_W-1:0] cacheTag;
  logic [ENTRIES-1:0][63:0] cacheData;
  logic [EIDX_W-1:0] cacheNext;

  // Walker.
  typedef enum logic [1:0] {
    WALK_IDLE = 2'd0,
    WALK_L0   = 2'd1,
    WALK_L1   = 2'd2
  } walk_state_e;
  walk_state_e walkState;
  logic [ADDR_W-1:0] walkAddr;
  logic [ADDR_W-1:0] walkEntryAddr;
  logic [HNF_W-1:0] walkHnf;
  logic walkStale;
  logic [HOME_W-1:0] walkPointer;

  int unsigned granuleShift;
  int unsigned l1Shift;
  int unsigned l0Bits;
  int unsigned ppsBits;

  always_comb begin
    granuleShift = gpcGranuleShift(pgs);
    l1Shift = granuleShift + 4;
    l0Bits = gpcL0Bits(l0gptsz);
    ppsBits = gpcPpsBits(pps);
  end

  // ---------------------------------------------------------------------
  // Checks.
  // ---------------------------------------------------------------------
  logic [NUM_HOMES-1:0] checkMalformed;
  logic [NUM_HOMES-1:0] checkMiss;

  always_comb begin
    for (int unsigned home = 0; home < NUM_HOMES; home++) begin
      logic [ADDR_W-1:0] addr;
      logic [3:0] gpi;
      logic found;
      logic [ADDR_W-1:0] offset;
      addr = checkAddr[home] & ((ADDR_W'(1) << CFG.addrW) - 1);
      checkDone[home] = 1'b1;
      checkFail[home] = 1'b0;
      checkMalformed[home] = 1'b0;
      checkMiss[home] = 1'b0;
      gpi = GPI_ALL_ACCESS;
      if (enable) begin
        if (CFG.gpcMode == GPC_TABLE) begin
          offset = addr - tableBase;
          if ((addr >= tableBase)
              && ((offset >> granuleShift) < ADDR_W'(GRANULES))) begin
            gpi = gpiTable[GIDX_W'(offset >> granuleShift)];
            checkFail[home] = !gpiPermits(gpi, checkPas[home]);
          end
        end else if (CFG.gpcMode == GPC_WALK) begin
          if ((ppsBits < ADDR_W) && ((addr >> ppsBits) != '0)) begin
            // Beyond the protected physical address size.
            checkFail[home] = 1'b1;
          end else begin
            found = 1'b0;
            for (int unsigned e = 0; e < ENTRIES; e++)
              if (!found && cacheValid[e]
                  && (cacheTag[e] == (addr >> (cacheLevel1[e] ? l1Shift : l0Bits)))) begin
                found = 1'b1;
                if (cacheFault[e]) begin
                  checkFail[home] = 1'b1;
                  checkMalformed[home] = 1'b1;
                end else begin
                  gpi = cacheLevel1[e]
                        ? cacheData[e][int'((addr >> granuleShift) & 'hf)*4 +: 4]
                        : cacheData[e][3:0];
                  checkFail[home] = !gpiPermits(gpi, checkPas[home]);
                  checkMalformed[home] = !(gpi inside {GPI_NO_ACCESS, GPI_SECURE,
                                                       GPI_NON_SECURE, GPI_ROOT,
                                                       GPI_REALM, GPI_ALL_ACCESS});
                end
              end
            checkDone[home] = found;
            checkMiss[home] = checkValid[home] && !found;
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------------
  // Walker: one walk at a time, for the next Home in rotation whose check
  // missed.
  // ---------------------------------------------------------------------
  logic walkStart;
  logic [HOME_W-1:0] walkHome;
  logic [63:0] walkDescriptor;
  logic walkReadDone;
  logic walkReadError;
  logic invalidateAll;
  logic invalidateByPa;
  logic [ADDR_W-1:0] invalidateAddr;

  always_comb begin
    int unsigned candidate;
    walkStart = 1'b0;
    walkHome = '0;
    if ((CFG.gpcMode == GPC_WALK) && (walkState == WALK_IDLE))
      for (int unsigned offset = 0; offset < NUM_HOMES; offset++) begin
        candidate = (int'(walkPointer) + offset) % NUM_HOMES;
        if (!walkStart && checkMiss[candidate]) begin
          walkStart = 1'b1;
          walkHome = HOME_W'(candidate);
        end
      end
    walkReadDone = (walkState != WALK_IDLE) && gptReadDone[walkHnf];
    walkReadError = gptReadError[walkHnf];
    walkDescriptor = gptReadData[walkHnf][int'(walkEntryAddr[5:3])*64 +: 64];
    gptReadAddr = {walkEntryAddr[ADDR_W-1:6], 6'b0};
    gptReadValid = '0;
    if (walkState != WALK_IDLE)
      gptReadValid[walkHnf] = 1'b1;
    walking = walkState != WALK_IDLE;
  end

  // ---------------------------------------------------------------------
  // APB.
  // ---------------------------------------------------------------------
  logic transfer;
  logic implemented;
  logic [31:0] strobed;
  logic writeOk;

  always_comb begin
    transfer = PSEL && PENABLE;
    PREADY = 1'b1;
    PRDATA = '0;
    implemented = 1'b1;
    case (PADDR)
      ADDR_CTRL:          PRDATA = {20'b0, l0gptsz, 1'b0, pps, 1'b0, pgs, enable};
      ADDR_TABLE_BASE_LO: PRDATA = tableBase[31:0];
      ADDR_TABLE_BASE_HI: PRDATA = 32'(tableBase >> 32);
      ADDR_GPT_BASE_LO:   PRDATA = gptBase[31:0];
      ADDR_GPT_BASE_HI:   PRDATA = 32'(gptBase >> 32);
      ADDR_GPI_INDEX:     PRDATA = 32'(gpiIndex);
      ADDR_GPI_DATA:
        for (int unsigned k = 0; k < 8; k++)
          if ((int'(gpiIndex & ~GIDX_W'(7)) + k) < GRANULES)
            PRDATA[k*4 +: 4] = gpiTable[int'(gpiIndex & ~GIDX_W'(7)) + k];
      ADDR_INVALIDATE:    PRDATA = '0;
      ADDR_INV_ADDR_LO:   PRDATA = invAddr[31:0];
      ADDR_INV_ADDR_HI:   PRDATA = 32'(invAddr >> 32);
      ADDR_FAULT_STATUS:  PRDATA = {faultCount, 15'b0, faultValid};
      ADDR_FAULT_ADDR_LO: PRDATA = faultAddr[31:0];
      ADDR_FAULT_ADDR_HI: PRDATA = 32'(faultAddr >> 32);
      ADDR_FAULT_INFO:    PRDATA = {5'b0, 11'(faultSrcId), 12'b0, faultMalformed, faultPas};
      ADDR_STATUS:        PRDATA = {31'b0, walking};
      default:            implemented = 1'b0;
    endcase
    strobed = PRDATA;
    for (int unsigned lane = 0; lane < 4; lane++)
      if (PSTRB[lane])
        strobed[lane*8 +: 8] = PWDATA[lane*8 +: 8];
    PSLVERR = transfer && ((PADDR[1:0] != 2'b00) || !implemented
                           || (PWRITE && (PPROT[1] || !PNSE))
                           || (PWRITE && (PADDR == ADDR_STATUS)));
    writeOk = transfer && PWRITE && !PSLVERR;

    invalidateAll = dvmInvalidateAll
                    || (writeOk && (PADDR == ADDR_INVALIDATE) && strobed[0])
                    || (writeOk && ((PADDR == ADDR_CTRL) || (PADDR == ADDR_GPT_BASE_LO)
                                    || (PADDR == ADDR_GPT_BASE_HI)));
    invalidateByPa = dvmInvalidateByPa
                     || (writeOk && (PADDR == ADDR_INVALIDATE) && strobed[1]);
    invalidateAddr = dvmInvalidateByPa ? dvmInvalidateAddr : invAddr;
  end

  // ---------------------------------------------------------------------
  // State.
  // ---------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!resetn) begin
      enable <= RESET_ENABLE;
      pgs <= '0;
      pps <= 3'b101;
      l0gptsz <= '0;
      tableBase <= '0;
      gptBase <= '0;
      gpiIndex <= '0;
      invAddr <= '0;
      for (int unsigned g = 0; g < GRANULES; g++)
        gpiTable[g] <= RESET_GPI;
      faultValid <= 1'b0;
      faultCount <= '0;
      faultAddr <= '0;
      faultPas <= PAS_SECURE;
      faultMalformed <= 1'b0;
      faultSrcId <= '0;
      cacheValid <= '0;
      cacheLevel1 <= '0;
      cacheFault <= '0;
      cacheTag <= '0;
      cacheData <= '0;
      cacheNext <= '0;
      walkState <= WALK_IDLE;
      walkAddr <= '0;
      walkEntryAddr <= '0;
      walkHnf <= '0;
      walkStale <= 1'b0;
      walkPointer <= '0;
    end else begin
      // Registers.
      if (writeOk) begin
        case (PADDR)
          ADDR_CTRL: begin
            enable <= strobed[0];
            pgs <= strobed[2:1];
            pps <= strobed[6:4];
            l0gptsz <= strobed[11:8];
          end
          ADDR_TABLE_BASE_LO: tableBase[31:0] <= strobed;
          ADDR_TABLE_BASE_HI: tableBase[ADDR_W-1:32] <= strobed[ADDR_W-33:0];
          ADDR_GPT_BASE_LO:   gptBase[31:0] <= {strobed[31:12], 12'b0};
          ADDR_GPT_BASE_HI:   gptBase[ADDR_W-1:32] <= strobed[ADDR_W-33:0];
          ADDR_GPI_INDEX:     gpiIndex <= strobed[GIDX_W-1:0];
          ADDR_GPI_DATA:
            for (int unsigned k = 0; k < 8; k++)
              if ((int'(gpiIndex & ~GIDX_W'(7)) + k) < GRANULES)
                gpiTable[int'(gpiIndex & ~GIDX_W'(7)) + k] <= strobed[k*4 +: 4];
          ADDR_INV_ADDR_LO:   invAddr[31:0] <= strobed;
          ADDR_INV_ADDR_HI:   invAddr[ADDR_W-1:32] <= strobed[ADDR_W-33:0];
          ADDR_FAULT_STATUS:
            if (strobed[0]) begin
              faultValid <= 1'b0;
              faultCount <= '0;
            end
          default: begin
          end
        endcase
      end

      // Fault record: the first fault is kept until cleared; every fault is
      // counted.
      for (int unsigned home = NUM_HOMES; home > 0; home--)
        if (checkValid[home-1] && checkDone[home-1] && checkFail[home-1]) begin
          if (!faultValid) begin
            faultAddr <= checkAddr[home-1];
            faultPas <= checkPas[home-1];
            faultMalformed <= checkMalformed[home-1];
            faultSrcId <= checkSrcId[home-1];
          end
          faultValid <= 1'b1;
        end
      begin
        int unsigned fails;
        fails = 0;
        for (int unsigned home = 0; home < NUM_HOMES; home++)
          if (checkValid[home] && checkDone[home] && checkFail[home])
            fails++;
        if ((32'(faultCount) + fails) > 32'hffff)
          faultCount <= '1;
        else
          faultCount <= faultCount + 16'(fails);
      end

      // Walker.
      case (walkState)
        WALK_IDLE:
          if (walkStart) begin
            walkAddr <= checkAddr[walkHome];
            // The level 0 entry for the address.
            walkEntryAddr <= gptBase
                             + (((checkAddr[walkHome]
                                  & ((ADDR_W'(1) << ppsBits) - 1)) >> l0Bits) << 3);
            walkHnf <= HNF_W'(hnHashIndex(CFG, gptBase
                       + (((checkAddr[walkHome]
                            & ((ADDR_W'(1) << ppsBits) - 1)) >> l0Bits) << 3)));
            walkStale <= 1'b0;
            walkState <= WALK_L0;
            walkPointer <= (int'(walkHome) == (NUM_HOMES - 1)) ? '0 : (walkHome + 1'b1);
          end
        WALK_L0:
          if (walkReadDone) begin
            if (!walkReadError && (walkDescriptor[3:0] == 4'b0011)) begin
              // Table descriptor: read the level 1 entry.
              walkEntryAddr <= {walkDescriptor[51:12], 12'b0}
                               + (((walkAddr & ((ADDR_W'(1) << l0Bits) - 1))
                                   >> l1Shift) << 3);
              walkHnf <= HNF_W'(hnHashIndex(CFG, {walkDescriptor[51:12], 12'b0}
                         + (((walkAddr & ((ADDR_W'(1) << l0Bits) - 1))
                             >> l1Shift) << 3)));
              walkState <= WALK_L1;
            end else begin
              // A block descriptor, or a fault for the whole level 0 region.
              if (!walkStale) begin
                cacheValid[cacheNext] <= 1'b1;
                cacheLevel1[cacheNext] <= 1'b0;
                cacheFault[cacheNext] <= walkReadError
                                         || (walkDescriptor[3:0] != 4'b0001);
                cacheTag[cacheNext] <= walkAddr >> l0Bits;
                cacheData[cacheNext] <= {60'b0, walkDescriptor[7:4]};
                cacheNext <= (int'(cacheNext) == (ENTRIES - 1)) ? '0 : (cacheNext + 1'b1);
              end
              walkState <= WALK_IDLE;
            end
          end
        WALK_L1:
          if (walkReadDone) begin
            if (!walkStale) begin
              cacheValid[cacheNext] <= 1'b1;
              cacheLevel1[cacheNext] <= 1'b1;
              cacheFault[cacheNext] <= walkReadError;
              cacheTag[cacheNext] <= walkAddr >> l1Shift;
              cacheData[cacheNext] <= walkDescriptor;
              cacheNext <= (int'(cacheNext) == (ENTRIES - 1)) ? '0 : (cacheNext + 1'b1);
            end
            walkState <= WALK_IDLE;
          end
        default:
          walkState <= WALK_IDLE;
      endcase

      // Invalidation. A walk in flight across an invalidation does not fill
      // the cache: its result may be what the invalidation removed.
      if (invalidateAll) begin
        cacheValid <= '0;
        if (walkState != WALK_IDLE)
          walkStale <= 1'b1;
      end else if (invalidateByPa) begin
        for (int unsigned e = 0; e < ENTRIES; e++)
          if (cacheValid[e]
              && (cacheTag[e] == (invalidateAddr >> (cacheLevel1[e] ? l1Shift : l0Bits))))
            cacheValid[e] <= 1'b0;
        if ((walkState != WALK_IDLE)
            && ((walkAddr >> l0Bits) == (invalidateAddr >> l0Bits)))
          walkStale <= 1'b1;
      end
    end
  end

  always_comb begin
    eventFault = 1'b0;
    for (int unsigned home = 0; home < NUM_HOMES; home++)
      if (checkValid[home] && checkDone[home] && checkFail[home])
        eventFault = 1'b1;
  end
endmodule
