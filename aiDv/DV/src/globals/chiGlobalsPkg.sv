// Testbench-wide configuration, derived counts and TB-only types.
//
// This package is imported by both the HDL and the HVL side, so it must stay
// free of UVM: parameters, typedefs, enums, structs and pure functions only.
// Anything that needs uvm_object lives in the role packages instead.
//
// Everything the DUT already defines is reused rather than restated. chi_pkg
// owns the flit structs, the opcode enumerations, the pack and unpack
// functions and the NodeID codec, so a second copy here would be a second
// thing to keep in step. What is left is the configuration the TB owns, the
// instance counts derived from it, and the handful of types that describe
// testbench activity rather than protocol content.
package chiGlobalsPkg;
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  // ---------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------
  // The TB starts from the DUT's own default so that the two cannot drift,
  // and overrides only what a run asks for. hdlTop passes the result back
  // into the DUT, which keeps this the single source of truth: there is no
  // way for the fabric to be built to one configuration and checked against
  // another.
  //
  // Node counts are deliberately left at the DUT default. defaultMeshPlacement
  // enumerates ordinals 0 to 13 only, and the ordinal of every node after the
  // one being resized shifts, so raising numRnd or numRnf past the default
  // silently invalidates the default placement table. Changing counts requires
  // supplying PLACEMENTS explicitly. See OPEN QUESTIONS.
  function automatic chi_cfg_t buildChiCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
`ifdef CHI_TB_NUM_RNF
    cfg.numRnf = `CHI_TB_NUM_RNF;
`endif
`ifdef CHI_TB_NUM_RND
    cfg.numRnd = `CHI_TB_NUM_RND;
`endif
`ifdef CHI_TB_NUM_RNI
    cfg.numRni = `CHI_TB_NUM_RNI;
`endif
`ifdef CHI_TB_NUM_SNF
    cfg.numSnf = `CHI_TB_NUM_SNF;
`endif
`ifdef CHI_TB_NUM_SNI
    cfg.numSni = `CHI_TB_NUM_SNI;
`endif
`ifdef CHI_TB_LCRD_DEPTH
    cfg.lcrdDepth = `CHI_TB_LCRD_DEPTH;
`endif
`ifdef CHI_TB_PARITY_EN
    cfg.parityEn = 1'b1;
`endif
    // Stage 1 turns off the three direct transfer optimisations. With DMT or
    // DWT the Subordinate responds straight to the Requester instead of to the
    // Home, and with DCT a snooped Requester forwards data to the requesting
    // one [SPEC:IHI0050H B2.3.3]. Each is a distinct response routing, and a
    // Subordinate model that answered the Home while the fabric expected it to
    // answer the Requester would deadlock rather than fail a check. They are
    // exercised in Stage 2, once the plain Home-mediated flow is known good.
`ifndef CHI_TB_ENABLE_DIRECT
    cfg.dmtEn = 1'b0;
    cfg.dwtEn = 1'b0;
    cfg.dctEn = 1'b0;
`endif
    return cfg;
  endfunction

  parameter chi_cfg_t CHI_CFG = buildChiCfg();

  // ---------------------------------------------------------------------
  // Derived counts and ordinal map
  // ---------------------------------------------------------------------
  // NUM_NODES must equal the sum of the eight class counts [CFGDOC:#3.3], and
  // the ordinal order below is the one nodeClassForOrdinal walks, so the TB
  // and the fabric agree on which ordinal names which node.
  localparam int unsigned NUM_NODES = CHI_CFG.numRnf + CHI_CFG.numRnd
      + CHI_CFG.numRni + CHI_CFG.numSnf + CHI_CFG.numSni
      + CHI_CFG.numHnf + CHI_CFG.numHni + CHI_CFG.numMn;

  localparam int unsigned OFF_RNF = 0;
  localparam int unsigned OFF_RND = OFF_RNF + CHI_CFG.numRnf;
  localparam int unsigned OFF_RNI = OFF_RND + CHI_CFG.numRnd;
  localparam int unsigned OFF_SNF = OFF_RNI + CHI_CFG.numRni;
  localparam int unsigned OFF_SNI = OFF_SNF + CHI_CFG.numSnf;
  localparam int unsigned OFF_HNF = OFF_SNI + CHI_CFG.numSni;
  localparam int unsigned OFF_HNI = OFF_HNF + CHI_CFG.numHnf;
  localparam int unsigned OFF_MN  = OFF_HNI + CHI_CFG.numHni;

  // Only the five external classes get an agent. HN-F, HN-I and MN are inside
  // the fabric and have no link, which is why the DUT reports linkUp as zero
  // for their ordinals.
  localparam int unsigned NUM_REQUESTER_AGENTS =
      CHI_CFG.numRnf + CHI_CFG.numRnd + CHI_CFG.numRni;
  localparam int unsigned NUM_SUBORDINATE_AGENTS =
      CHI_CFG.numSnf + CHI_CFG.numSni;
  localparam int unsigned NUM_EXTERNAL_PORTS =
      NUM_REQUESTER_AGENTS + NUM_SUBORDINATE_AGENTS;

  // The DUT declares each interface array as max(count,1) so that a zero
  // count still elaborates, and the TB has to size its arrays identically or
  // the port connection is a width mismatch.
  localparam int unsigned NUM_RNF_IF = (CHI_CFG.numRnf > 0) ? CHI_CFG.numRnf : 1;
  localparam int unsigned NUM_RND_IF = (CHI_CFG.numRnd > 0) ? CHI_CFG.numRnd : 1;
  localparam int unsigned NUM_RNI_IF = (CHI_CFG.numRni > 0) ? CHI_CFG.numRni : 1;
  localparam int unsigned NUM_SNF_IF = (CHI_CFG.numSnf > 0) ? CHI_CFG.numSnf : 1;
  localparam int unsigned NUM_SNI_IF = (CHI_CFG.numSni > 0) ? CHI_CFG.numSni : 1;

  // ---------------------------------------------------------------------
  // Widths
  // ---------------------------------------------------------------------
  function automatic int unsigned chiMaxOf4(input int unsigned a,
                                            input int unsigned b,
                                            input int unsigned c,
                                            input int unsigned d);
    int unsigned value;
    value = a;
    if (b > value) value = b;
    if (c > value) value = c;
    if (d > value) value = d;
    return value;
  endfunction

  localparam int unsigned CHI_ADDR_W    = CHI_CFG.addrW;
  localparam int unsigned CHI_DATA_W    = CHI_CFG.dataW;
  localparam int unsigned CHI_NODEID_W  = CHI_CFG.nodeIdW;

  localparam int unsigned REQ_FLIT_W = reqFlitWidth(CHI_CFG);
  localparam int unsigned RSP_FLIT_W = rspFlitWidth(CHI_CFG);
  localparam int unsigned SNP_FLIT_W = snpFlitWidth(CHI_CFG);
  localparam int unsigned DAT_FLIT_W = datFlitWidth(CHI_CFG);

  // A cache line is 64 bytes and CHI addresses it with the low 6 bits
  // [SPEC:IHI0050H B2.3.1]. interleaveGranule defaults to the same 64 bytes,
  // but it selects a Home Node rather than sizing a line, so the two are kept
  // separate.
  localparam int unsigned CHI_LINE_BYTES  = 64;
  localparam int unsigned CHI_LINE_OFF_W  = 6;
  localparam int unsigned CHI_LINE_ADDR_W = CHI_ADDR_W - CHI_LINE_OFF_W;

  // Packets needed to move one full line over the data bus, which is what
  // both the driver and the scoreboard count DAT flits against
  // [SPEC:IHI0050H B2.9.4].
  localparam int unsigned CHI_DAT_PKTS_PER_LINE =
      (CHI_LINE_BYTES * 8) / CHI_DATA_W;

  typedef logic [CHI_ADDR_W-1:0]      chiAddrT;
  typedef logic [CHI_LINE_ADDR_W-1:0] chiLineAddrT;
  typedef logic [CHI_DATA_W-1:0]      chiDataT;
  typedef logic [CHI_MAX_NODEID_W-1:0] chiNodeIdT;
  typedef logic [CHI_TXNID_FLIT_W-1:0] chiTxnIdT;
  typedef logic [7:0]                  chiByteT;
  typedef chiByteT                     chiLineBytesT [CHI_LINE_BYTES];

  // TxnID is unique only within the transactions from one source node
  // [SPEC:IHI0050H B2.3.2], so nothing may be keyed on TxnID alone.
  typedef struct packed {
    chiNodeIdT srcId;
    chiTxnIdT  txnId;
  } chiTxnKeyT;

  // ---------------------------------------------------------------------
  // Node classification
  // ---------------------------------------------------------------------
  // chi_node_class_e already names the eight classes, so the TB uses it
  // directly and adds only the predicates that express what a class is allowed
  // to do. The spec terms: RN-F is fully coherent, RN-D is I/O coherent with
  // DVM support, RN-I is I/O coherent without it [SPEC:IHI0050H B1.6.1].
  function automatic bit isRequesterClass(input chi_node_class_e nodeClass);
    return (nodeClass == NODE_RNF) || (nodeClass == NODE_RND)
           || (nodeClass == NODE_RNI);
  endfunction

  function automatic bit isSubordinateClass(input chi_node_class_e nodeClass);
    return (nodeClass == NODE_SNF) || (nodeClass == NODE_SNI);
  endfunction

  // A fully coherent Requester is the only class that holds cacheable state
  // and so the only one that can be snooped [SPEC:IHI0050H B1.6.1].
  function automatic bit isFullyCoherent(input chi_node_class_e nodeClass);
    return (nodeClass == NODE_RNF);
  endfunction

  function automatic bit isIoCoherent(input chi_node_class_e nodeClass);
    return (nodeClass == NODE_RND) || (nodeClass == NODE_RNI);
  endfunction

  function automatic bit hasDvmSupport(input chi_node_class_e nodeClass);
    return (nodeClass == NODE_RND) && CHI_CFG.dvmEn;
  endfunction

  // Agent index to class. Requester and Subordinate agents are numbered
  // separately, each in the same order as the node ordinals, so that an agent
  // index can be turned into an ordinal and back.
  function automatic chi_node_class_e requesterClassOf(input int unsigned agentId);
    if (agentId < CHI_CFG.numRnf) return NODE_RNF;
    if (agentId < (CHI_CFG.numRnf + CHI_CFG.numRnd)) return NODE_RND;
    return NODE_RNI;
  endfunction

  function automatic chi_node_class_e subordinateClassOf(input int unsigned agentId);
    if (agentId < CHI_CFG.numSnf) return NODE_SNF;
    return NODE_SNI;
  endfunction

  function automatic int unsigned requesterOrdinalOf(input int unsigned agentId);
    return OFF_RNF + agentId;
  endfunction

  function automatic int unsigned subordinateOrdinalOf(input int unsigned agentId);
    return OFF_SNF + agentId;
  endfunction

  // Index of an agent within its own class, which is what indexes the DUT's
  // per-class interface arrays.
  function automatic int unsigned requesterClassIndexOf(input int unsigned agentId);
    if (agentId < CHI_CFG.numRnf) return agentId;
    if (agentId < (CHI_CFG.numRnf + CHI_CFG.numRnd))
      return agentId - CHI_CFG.numRnf;
    return agentId - CHI_CFG.numRnf - CHI_CFG.numRnd;
  endfunction

  function automatic int unsigned subordinateClassIndexOf(input int unsigned agentId);
    if (agentId < CHI_CFG.numSnf) return agentId;
    return agentId - CHI_CFG.numSnf;
  endfunction

  function automatic chiNodeIdT nodeIdOf(input int unsigned ordinal);
    return defaultNodeId(CHI_CFG, ordinal);
  endfunction

  // ---------------------------------------------------------------------
  // Channel applicability
  // ---------------------------------------------------------------------
  // Which channels a node of a given class actually uses, per direction.
  // A Requester transmits REQ, RSP and DAT and receives RSP, SNP and DAT; a
  // Subordinate transmits RSP and DAT and receives REQ, RSP and DAT
  // [SPEC:IHI0050H B13.3]. The node never transmits snoops in either class.
  //
  // Two cases are deliberately wider than the protocol strictly needs, and
  // they match what the fabric's own link ports do. A Subordinate is given a
  // receive RSP channel even though the spec shows no protocol RSP arriving at
  // one, and an RN-I is given a receive SNP channel even though an I/O coherent
  // Requester is never snooped. In both cases the channel exists at the link
  // layer and must be credited or activation cannot complete; the protocol
  // layer treats any real flit on them as an error. See OPEN QUESTIONS.
  typedef enum bit [1:0] {
    CHI_DIR_TX = 2'b00,
    CHI_DIR_RX = 2'b01
  } chiDirectionE;

  function automatic bit channelApplies(
    input chi_node_class_e  nodeClass,
    input chiDirectionE  direction,
    input chi_channel_e  channel
  );
    bit requester;
    requester = isRequesterClass(nodeClass);
    if (direction == CHI_DIR_TX) begin
      case (channel)
        CHI_CHANNEL_REQ: return requester;
        CHI_CHANNEL_RSP: return 1'b1;
        CHI_CHANNEL_SNP: return 1'b0;
        CHI_CHANNEL_DAT: return 1'b1;
        default:         return 1'b0;
      endcase
    end else begin
      case (channel)
        CHI_CHANNEL_REQ: return !requester;
        CHI_CHANNEL_RSP: return 1'b1;
        CHI_CHANNEL_SNP: return requester;
        CHI_CHANNEL_DAT: return 1'b1;
        default:         return 1'b0;
      endcase
    end
  endfunction

  // ---------------------------------------------------------------------
  // Link layer observation
  // ---------------------------------------------------------------------
  // The RTL link FSM encodes its states module-locally, so the TB restates
  // the encoding here to decode the same values [SPEC:IHI0050H B14.5.1
  // Table B14.1, link/chi_link_fsm.sv].
  typedef enum bit [1:0] {
    CHI_LINK_STOP       = 2'b00,
    CHI_LINK_ACTIVATE   = 2'b01,
    CHI_LINK_RUN        = 2'b10,
    CHI_LINK_DEACTIVATE = 2'b11
  } chiLinkStateE;

  // One monitor analysis port carries both protocol flits and link events, so
  // a subscriber needs to know which it has been handed before reading any
  // other field.
  typedef enum bit [1:0] {
    CHI_TX_PROTOCOL_FLIT = 2'b00,
    CHI_TX_LINK_EVENT    = 2'b01
  } chiTxKindE;

  typedef enum bit [2:0] {
    CHI_LINK_EVT_STATE_CHANGE = 3'b000,
    CHI_LINK_EVT_CREDIT_GRANT = 3'b001,
    CHI_LINK_EVT_CREDIT_USE   = 3'b010,
    CHI_LINK_EVT_CREDIT_ERROR = 3'b011,
    CHI_LINK_EVT_SYSCO        = 3'b100
  } chiLinkEventKindE;

  typedef struct {
    chiLinkEventKindE kind;
    chiDirectionE     direction;
    chi_channel_e     channel;
    chiLinkStateE     state;
    int unsigned      creditCount;
    bit               sysCoReq;
    bit               sysCoAck;
  } chiLinkEventS;

  // What a monitor BFM hands its proxy for one observed flit. The flit is
  // carried in a container wide enough for any channel and the proxy unpacks it
  // with the function for the channel named here, so a narrower channel simply
  // leaves the upper bits clear.
  //
  // The container is sized by the architectural maxima rather than by this
  // configuration's flit widths, because the unpack functions take a
  // maximum-width argument and the proxy slices the container to that width
  // before calling them. Sizing it to the configured DAT width, which is
  // narrower than CHI_MAX_DAT_FLIT_W whenever the data bus is below its widest
  // legal value, makes that slice run off the end of the vector and yield X.
  localparam int unsigned CHI_WIDEST_FLIT_W =
      chiMaxOf4(CHI_MAX_REQ_FLIT_W, CHI_MAX_RSP_FLIT_W,
                CHI_MAX_SNP_FLIT_W, CHI_MAX_DAT_FLIT_W);

  typedef struct {
    chiDirectionE                direction;
    chi_channel_e                channel;
    logic [CHI_WIDEST_FLIT_W-1:0] flit;
  } chiSampledFlitS;

  // ---------------------------------------------------------------------
  // Stimulus intent
  // ---------------------------------------------------------------------
  // Sequences ask for an access in these terms and the driver proxy decides
  // which opcode realises it, because the choice depends on cache state that
  // only the driver can see.
  typedef enum bit [2:0] {
    CHI_ACCESS_READ        = 3'b000,
    CHI_ACCESS_WRITE       = 3'b001,
    CHI_ACCESS_READ_UNIQUE = 3'b010,
    CHI_ACCESS_CLEAN       = 3'b011,
    CHI_ACCESS_EVICT       = 3'b100
  } chiAccessKindE;

  // What a Requester must do about a snoop: the state its line ends up in,
  // whether it owes data back, and whether that data carries the dirty
  // responsibility with it [SPEC:IHI0050H B4.9].
  typedef struct {
    chi_cache_state_e nextState;
    chi_resp_e        respState;
    bit               sendData;
    bit               passDirty;
  } chiSnoopActionS;

  // ---------------------------------------------------------------------
  // Address helpers
  // ---------------------------------------------------------------------
  function automatic chiLineAddrT lineAddrOf(input chiAddrT addr);
    return addr[CHI_ADDR_W-1:CHI_LINE_OFF_W];
  endfunction

  function automatic chiAddrT lineBaseOf(input chiAddrT addr);
    chiAddrT base;
    base = addr;
    base[CHI_LINE_OFF_W-1:0] = '0;
    return base;
  endfunction

  // Deterministic memory contents, shared by the Subordinate memory model and
  // the scoreboard's reference copy. Both derive the same byte from the
  // address instead of exchanging an image, so a mismatch means the fabric
  // moved the wrong data rather than that the two models were loaded
  // differently.
  function automatic chiByteT memInitByte(input chiAddrT addr);
    chiByteT value;
    value = chiByteT'(addr[7:0] ^ addr[15:8] ^ addr[23:16] ^ 8'hA5);
    return value;
  endfunction
endpackage
