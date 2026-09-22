//==============================================================================
// chiLinkLayerBfm.svh
//
// Why one included file instead of two copies, or a base class:
//
// The link layer is identical on a Requester port and on a Subordinate port.
// The activation handshake, the L-Credit accounting, the credit drain on
// deactivation and the system coherency handshake do not depend on the node
// class at all; only the *set of channels in use* does. Writing it twice would
// mean fixing every credit bug twice, and a class cannot do it because the
// whole point is that it touches pins. So it is written once here and included
// into chiRequesterDriverBfm and chiSubordinateDriverBfm, which differ only in
// the IS_REQUESTER parameter and in the transaction-level tasks they add.
//
// Deliberately macro-free. A macro defined here would be defined twice when
// this file is included twice into one compilation unit, and guarding it with
// `ifndef breaks whichever inclusion comes second when the tool puts each file
// in its own unit. Per-channel code is therefore written out explicitly.
//
// Signal ownership, which is what keeps this from creating multiple drivers:
//   driven here  - TXLINKACTIVEREQ, RXLINKACTIVEACK, every node-side TX flit
//                  signal (FLITPEND, FLITV, FLIT and the multi-bit FLITCHK) on
//                  all four channels including the ones this port class never
//                  uses, the RX*LCRDV of every channel this port receives on,
//                  and SYSCOREQ.
//   never driven - CLK and RESETn, which the DUT drives onto the interface
//                  [ASSUMPTION:2]; TXSACTIVE and RXSACTIVE, which the DUT also
//                  drives, contrary to the specification making TXSACTIVE a
//                  node output [ASSUMPTION:3]; every single-bit *CHK companion,
//                  which the DUT drives to zero on both sides [ASSUMPTION:1];
//                  SYSCOACK; and anything in the RX flit direction.
//
// [SPEC:IHI0050H B13.5 Link activation and deactivation]
// [SPEC:IHI0050H B13.7 Link credits]
//==============================================================================

  //----------------------------------------------------------------------------
  // Identity and channel usage
  //
  // The node interface reaches this BFM as a flat list of signal ports,
  // declared by the enclosing file and connected by hdlTop, rather than as a
  // chi_if port or a virtual chi_if member. Both of those are closed off:
  // "virtual interfaces shall not be used as ports, interface items, or as
  // members of unions" [SPEC:IEEE1800-2017 25.9], and an interface that has an
  // interface port cannot itself be the target of a virtual interface handle.
  // Every BFM here has to be reachable from its proxy through uvm_config_db,
  // so signal ports are the only legal connection.
  //
  // The width of each flit port is declared from chiGlobalsPkg, so a
  // disagreement between the testbench's flit model and the DUT's bus shows up
  // as a port connection width mismatch at compile time in hdlTop, not as
  // silently mispacked flits at run time.
  //
  // Identity is a run-time variable rather than a parameter for a related
  // reason: a parameterized interface is a distinct type per parameter value,
  // and one `virtual chiRequesterDriverBfm` handle has to be able to hold any
  // port's BFM.
  //----------------------------------------------------------------------------

  int unsigned                 nodeOrdinal;
  chiGlobalsPkg::chiNodeClassE nodeClass;
  bit                          isRequesterPort;

  bit useTxReq;     // a Requester sources requests
  bit useRxReq;     // a Subordinate sinks them
  bit useTxRsp;
  bit useRxRsp;
  bit useTxDat;
  bit useRxDat;
  bit useRxSnp;     // [TOP:CHI_CONNECT_PORT IS_REQUESTER]

  // Set by configure(). A proxy must not call linkInit() before this is set,
  // because hdlTop's configuration and run_test() both happen at time 0 in an
  // order the language does not define.
  bit configured;

  task automatic waitConfigured();
    wait (configured == 1'b1);
  endtask

  task automatic configure(input int unsigned ordinal,
                           input chiGlobalsPkg::chiNodeClassE portClass);
    nodeOrdinal     = ordinal;
    nodeClass       = portClass;
    isRequesterPort = chiGlobalsPkg::nodeClassIsRequester(portClass);
    useTxReq = isRequesterPort;
    useRxReq = !isRequesterPort;
    useTxRsp = 1'b1;
    useRxRsp = 1'b1;
    useTxDat = 1'b1;
    useRxDat = 1'b1;
    useRxSnp = isRequesterPort;
    configured = 1'b1;
  endtask

  // Widths used for slicing, taken from the flit ports this BFM declares,
  // which are themselves declared from chiGlobalsPkg. hdlTop compares them
  // against the chi_if buses at time 0 and reports any difference.
  localparam int unsigned IF_REQ_W = $bits(TXREQFLIT);
  localparam int unsigned IF_RSP_W = $bits(TXRSPFLIT);
  localparam int unsigned IF_DAT_W = $bits(TXDATFLIT);
  localparam int unsigned IF_SNP_W = $bits(RXSNPFLIT);

  localparam int unsigned IF_REQ_CHK_W = $bits(TXREQFLITCHK);
  localparam int unsigned IF_RSP_CHK_W = $bits(TXRSPFLITCHK);
  localparam int unsigned IF_DAT_CHK_W = $bits(TXDATFLITCHK);

  //----------------------------------------------------------------------------
  // Link state
  //----------------------------------------------------------------------------

  chiGlobalsPkg::chiLinkStateE txLinkState;
  chiGlobalsPkg::chiLinkStateE rxLinkState;

  // Credits this port holds, one counter per channel it transmits on.
  int unsigned txReqCredits;
  int unsigned txRspCredits;
  int unsigned txDatCredits;

  // Credits this port has advertised and not yet seen consumed, one counter per
  // channel it receives on. Never allowed above LCRD_DEPTH [ASSUMPTION:9].
  int unsigned rxReqCreditsOut;
  int unsigned rxRspCreditsOut;
  int unsigned rxDatCreditsOut;
  int unsigned rxSnpCreditsOut;

  // Totals, kept for the end-of-test credit reconciliation.
  int unsigned txReqCreditsSeen;
  int unsigned txRspCreditsSeen;
  int unsigned txDatCreditsSeen;
  int unsigned txReqFlitsSent;
  int unsigned txRspFlitsSent;
  int unsigned txDatFlitsSent;

  bit txActivateRequest;
  bit linkStarted;

  chiGlobalsPkg::chiRawFlitT rxReqQueue [$];
  chiGlobalsPkg::chiRawFlitT rxRspQueue [$];
  chiGlobalsPkg::chiRawFlitT rxDatQueue [$];
  chiGlobalsPkg::chiRawFlitT rxSnpQueue [$];

  semaphore txReqSem;
  semaphore txRspSem;
  semaphore txDatSem;

  // Error injection knobs, used only by the directed link tests. Default off so
  // that no functional test can trip the DUT's error outputs by accident.
  // See OPEN QUESTIONS Q17.
  bit          injectParityError;
  int unsigned injectParityBit;
  bit          injectSendWithoutCredit;
  bit          injectOddParity;

  //----------------------------------------------------------------------------
  // Initialisation
  //
  // Called by the driver proxy before reset is released. Everything the BFM
  // drives is given a value here and nowhere else at declaration, so no signal
  // has both a declaration initialiser and a reset assignment.
  //----------------------------------------------------------------------------

  task automatic linkInit();
    txLinkState = chiGlobalsPkg::LINK_STOP;
    rxLinkState = chiGlobalsPkg::LINK_STOP;
    txReqCredits = 0;
    txRspCredits = 0;
    txDatCredits = 0;
    rxReqCreditsOut = 0;
    rxRspCreditsOut = 0;
    rxDatCreditsOut = 0;
    rxSnpCreditsOut = 0;
    txReqCreditsSeen = 0;
    txRspCreditsSeen = 0;
    txDatCreditsSeen = 0;
    txReqFlitsSent = 0;
    txRspFlitsSent = 0;
    txDatFlitsSent = 0;
    txActivateRequest = 1'b0;
    linkStarted = 1'b0;
    injectParityError = 1'b0;
    injectParityBit = 0;
    injectSendWithoutCredit = 1'b0;
    injectOddParity = 1'b0;

    rxReqQueue.delete();
    rxRspQueue.delete();
    rxDatQueue.delete();
    rxSnpQueue.delete();

    txReqSem = new(1);
    txRspSem = new(1);
    txDatSem = new(1);

    TXLINKACTIVEREQ = 1'b0;
    RXLINKACTIVEACK = 1'b0;
    SYSCOREQ = 1'b0;

    TXREQFLITPEND = 1'b0;
    TXREQFLITV = 1'b0;
    TXREQFLIT = '0;
    TXREQFLITCHK = '0;

    TXRSPFLITPEND = 1'b0;
    TXRSPFLITV = 1'b0;
    TXRSPFLIT = '0;
    TXRSPFLITCHK = '0;

    TXDATFLITPEND = 1'b0;
    TXDATFLITV = 1'b0;
    TXDATFLIT = '0;
    TXDATFLITCHK = '0;

    // Nothing reads the node-side SNP transmit direction on any port class, but
    // it is a DUT input, so it is held at zero rather than left floating
    // [ASSUMPTION:1].
    TXSNPFLITPEND = 1'b0;
    TXSNPFLITV = 1'b0;
    TXSNPFLIT = '0;

    RXREQLCRDV = 1'b0;
    RXRSPLCRDV = 1'b0;
    RXDATLCRDV = 1'b0;
    RXSNPLCRDV = 1'b0;
  endtask

  //----------------------------------------------------------------------------
  // Link bring-up and tear-down control
  //----------------------------------------------------------------------------

  task automatic linkStart();
    if (linkStarted) return;
    linkStarted = 1'b1;
    fork
      txActivationLoop();
      rxActivationLoop();
      txCreditObserveLoop();
      rxCreditIssueLoop();
      rxCaptureLoop();
      txCreditDrainLoop();
    join_none
  endtask

  task automatic linkActivate();
    txActivateRequest = 1'b1;
    // Both directions must be usable before any transaction starts: the
    // transmit direction to send, the receive direction so that a response
    // cannot be dropped for want of a credit.
    wait ((txLinkState == chiGlobalsPkg::LINK_RUN) &&
          (rxLinkState == chiGlobalsPkg::LINK_RUN));
  endtask

  task automatic linkDeactivate();
    txActivateRequest = 1'b0;
    wait (txLinkState == chiGlobalsPkg::LINK_STOP);
  endtask

  function automatic bit linkIsRunning();
    return (txLinkState == chiGlobalsPkg::LINK_RUN) &&
           (rxLinkState == chiGlobalsPkg::LINK_RUN);
  endfunction

  // True when this port is transmitting nothing and holds no credit it has not
  // returned, which is the precondition for leaving RUN.
  function automatic bit txIsQuiet();
    bit quiet;
    quiet = 1'b1;
    if (useTxReq && (txReqCredits != 0)) quiet = 1'b0;
    if (useTxRsp && (txRspCredits != 0)) quiet = 1'b0;
    if (useTxDat && (txDatCredits != 0)) quiet = 1'b0;
    return quiet;
  endfunction

  function automatic bit rxCreditsAllReturned();
    return (rxReqCreditsOut == 0) && (rxRspCreditsOut == 0) &&
           (rxDatCreditsOut == 0) && (rxSnpCreditsOut == 0);
  endfunction

  //----------------------------------------------------------------------------
  // Activation state machines
  //
  // The transmit direction owns LINKACTIVEREQ and the receive direction owns
  // LINKACTIVEACK, so each of the two signals this BFM drives has exactly one
  // driving process.
  //----------------------------------------------------------------------------

  task automatic txActivationLoop();
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        TXLINKACTIVEREQ <= 1'b0;
        txLinkState = chiGlobalsPkg::LINK_STOP;
      end
      else begin
        case (txLinkState)
          chiGlobalsPkg::LINK_STOP: begin
            if (txActivateRequest) begin
              TXLINKACTIVEREQ <= 1'b1;
              txLinkState = chiGlobalsPkg::LINK_ACTIVATE;
            end
          end
          chiGlobalsPkg::LINK_ACTIVATE: begin
            if (TXLINKACTIVEACK === 1'b1)
              txLinkState = chiGlobalsPkg::LINK_RUN;
          end
          chiGlobalsPkg::LINK_RUN: begin
            // Leaving RUN is only legal with nothing left to send. The credits
            // still held are returned from the DEACTIVATE state.
            if (!txActivateRequest) begin
              TXLINKACTIVEREQ <= 1'b0;
              txLinkState = chiGlobalsPkg::LINK_DEACTIVATE;
            end
          end
          default: begin   // LINK_DEACTIVATE
            if ((TXLINKACTIVEACK === 1'b0) && txIsQuiet())
              txLinkState = chiGlobalsPkg::LINK_STOP;
          end
        endcase
      end
    end
  endtask

  task automatic rxActivationLoop();
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        RXLINKACTIVEACK <= 1'b0;
        rxLinkState = chiGlobalsPkg::LINK_STOP;
      end
      else begin
        case (rxLinkState)
          chiGlobalsPkg::LINK_STOP: begin
            // The DUT raises its transmit request as soon as reset is released,
            // so this branch is taken on the first clock after reset
            // [ASSUMPTION:16]. The ACTIVATE state is held for one cycle so the
            // handshake is observable rather than collapsing to zero width.
            if (RXLINKACTIVEREQ === 1'b1)
              rxLinkState = chiGlobalsPkg::LINK_ACTIVATE;
          end
          chiGlobalsPkg::LINK_ACTIVATE: begin
            RXLINKACTIVEACK <= 1'b1;
            rxLinkState = chiGlobalsPkg::LINK_RUN;
          end
          chiGlobalsPkg::LINK_RUN: begin
            if (RXLINKACTIVEREQ === 1'b0)
              rxLinkState = chiGlobalsPkg::LINK_DEACTIVATE;
          end
          default: begin   // LINK_DEACTIVATE
            // Hold the acknowledge until every credit handed out has come back,
            // which the remote transmitter does with LCrdReturn flits.
            if (rxCreditsAllReturned()) begin
              RXLINKACTIVEACK <= 1'b0;
              rxLinkState = chiGlobalsPkg::LINK_STOP;
            end
          end
        endcase
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Credit observation on the transmit side
  //----------------------------------------------------------------------------

  task automatic txCreditObserveLoop();
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        txReqCredits = 0;
        txRspCredits = 0;
        txDatCredits = 0;
      end
      else begin
        if (useTxReq && (TXREQLCRDV === 1'b1)) begin
          txReqCredits++;
          txReqCreditsSeen++;
        end
        if (useTxRsp && (TXRSPLCRDV === 1'b1)) begin
          txRspCredits++;
          txRspCreditsSeen++;
        end
        if (useTxDat && (TXDATLCRDV === 1'b1)) begin
          txDatCredits++;
          txDatCreditsSeen++;
        end
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Credit issue on the receive side
  //
  // One credit per clock, never more than LCRD_DEPTH outstanding, and only in
  // RUN. Going above the advertised depth makes the DUT raise linkCreditError,
  // so the bound is a protocol requirement rather than a politeness
  // [ASSUMPTION:9].
  //----------------------------------------------------------------------------

  task automatic rxCreditIssueLoop();
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        RXREQLCRDV <= 1'b0;
        RXRSPLCRDV <= 1'b0;
        RXDATLCRDV <= 1'b0;
        RXSNPLCRDV <= 1'b0;
        rxReqCreditsOut = 0;
        rxRspCreditsOut = 0;
        rxDatCreditsOut = 0;
        rxSnpCreditsOut = 0;
      end
      else begin
        RXREQLCRDV <= 1'b0;
        RXRSPLCRDV <= 1'b0;
        RXDATLCRDV <= 1'b0;
        RXSNPLCRDV <= 1'b0;
        if (rxLinkState == chiGlobalsPkg::LINK_RUN) begin
          if (useRxReq && (rxReqCreditsOut < chiGlobalsPkg::LCRD_DEPTH)) begin
            RXREQLCRDV <= 1'b1;
            rxReqCreditsOut++;
          end
          if (useRxRsp && (rxRspCreditsOut < chiGlobalsPkg::LCRD_DEPTH)) begin
            RXRSPLCRDV <= 1'b1;
            rxRspCreditsOut++;
          end
          if (useRxDat && (rxDatCreditsOut < chiGlobalsPkg::LCRD_DEPTH)) begin
            RXDATLCRDV <= 1'b1;
            rxDatCreditsOut++;
          end
          if (useRxSnp && (rxSnpCreditsOut < chiGlobalsPkg::LCRD_DEPTH)) begin
            RXSNPLCRDV <= 1'b1;
            rxSnpCreditsOut++;
          end
        end
      end
    end
  endtask

  // Deliberate over-advertisement, for the directed credit-error test only.
  task automatic injectExtraCredits(input chiGlobalsPkg::chiChannelE channel,
                                    input int unsigned count);
    for (int unsigned i = 0; i < count; i++) begin
      @(posedge CLK);
      case (channel)
        chiGlobalsPkg::CHI_CH_REQ: begin
          RXREQLCRDV <= 1'b1;
          rxReqCreditsOut++;
        end
        chiGlobalsPkg::CHI_CH_RSP: begin
          RXRSPLCRDV <= 1'b1;
          rxRspCreditsOut++;
        end
        chiGlobalsPkg::CHI_CH_SNP: begin
          RXSNPLCRDV <= 1'b1;
          rxSnpCreditsOut++;
        end
        default: begin
          RXDATLCRDV <= 1'b1;
          rxDatCreditsOut++;
        end
      endcase
    end
  endtask

  //----------------------------------------------------------------------------
  // Flit capture on the receive side
  //
  // Captured into a queue rather than handed straight to the proxy, so that a
  // proxy thread that is busy elsewhere cannot lose a flit. The credit that
  // carried the flit is released here, which is also what lets the receive
  // direction know when a deactivation drain is complete.
  //----------------------------------------------------------------------------

  task automatic rxCaptureLoop();
    forever begin
      @(posedge CLK);
      if (RESETn === 1'b1) begin
        if (useRxReq && (RXREQFLITV === 1'b1)) begin
          rxReqQueue.push_back(chiGlobalsPkg::chiRawFlitT'(RXREQFLIT));
          if (rxReqCreditsOut > 0) rxReqCreditsOut--;
        end
        if (useRxRsp && (RXRSPFLITV === 1'b1)) begin
          rxRspQueue.push_back(chiGlobalsPkg::chiRawFlitT'(RXRSPFLIT));
          if (rxRspCreditsOut > 0) rxRspCreditsOut--;
        end
        if (useRxDat && (RXDATFLITV === 1'b1)) begin
          rxDatQueue.push_back(chiGlobalsPkg::chiRawFlitT'(RXDATFLIT));
          if (rxDatCreditsOut > 0) rxDatCreditsOut--;
        end
        if (useRxSnp && (RXSNPFLITV === 1'b1)) begin
          rxSnpQueue.push_back(chiGlobalsPkg::chiRawFlitT'(RXSNPFLIT));
          if (rxSnpCreditsOut > 0) rxSnpCreditsOut--;
        end
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Flit transmission
  //
  // FLITPEND leads FLITV by one cycle, as the specification requires, even
  // though the DUT is expected to ignore it. Each channel has its own semaphore
  // so that two proxy threads sending on different channels do not serialise,
  // while two sending on the same channel cannot interleave and corrupt the
  // bus.
  //----------------------------------------------------------------------------

  task automatic sendReqFlit(input chiGlobalsPkg::chiRawFlitT flit,
                             input bit allowDuringDrain = 1'b0);
    logic [chiGlobalsPkg::CHK_MAX_W-1:0] chk;
    if (!useTxReq) return;
    txReqSem.get(1);
    waitSendWindow(chiGlobalsPkg::CHI_CH_REQ, allowDuringDrain);
    chk = flitCheckFor(flit, IF_REQ_W);
    TXREQFLITPEND <= 1'b1;
    @(posedge CLK);
    TXREQFLITPEND <= 1'b0;
    TXREQFLITV <= 1'b1;
    TXREQFLIT <= flit[IF_REQ_W-1:0];
    TXREQFLITCHK <= chk[IF_REQ_CHK_W-1:0];
    if (txReqCredits > 0) txReqCredits--;
    txReqFlitsSent++;
    @(posedge CLK);
    TXREQFLITV <= 1'b0;
    txReqSem.put(1);
  endtask

  task automatic sendRspFlit(input chiGlobalsPkg::chiRawFlitT flit,
                             input bit allowDuringDrain = 1'b0);
    logic [chiGlobalsPkg::CHK_MAX_W-1:0] chk;
    if (!useTxRsp) return;
    txRspSem.get(1);
    waitSendWindow(chiGlobalsPkg::CHI_CH_RSP, allowDuringDrain);
    chk = flitCheckFor(flit, IF_RSP_W);
    TXRSPFLITPEND <= 1'b1;
    @(posedge CLK);
    TXRSPFLITPEND <= 1'b0;
    TXRSPFLITV <= 1'b1;
    TXRSPFLIT <= flit[IF_RSP_W-1:0];
    TXRSPFLITCHK <= chk[IF_RSP_CHK_W-1:0];
    if (txRspCredits > 0) txRspCredits--;
    txRspFlitsSent++;
    @(posedge CLK);
    TXRSPFLITV <= 1'b0;
    txRspSem.put(1);
  endtask

  task automatic sendDatFlit(input chiGlobalsPkg::chiRawFlitT flit,
                             input bit allowDuringDrain = 1'b0);
    logic [chiGlobalsPkg::CHK_MAX_W-1:0] chk;
    if (!useTxDat) return;
    txDatSem.get(1);
    waitSendWindow(chiGlobalsPkg::CHI_CH_DAT, allowDuringDrain);
    chk = flitCheckFor(flit, IF_DAT_W);
    TXDATFLITPEND <= 1'b1;
    @(posedge CLK);
    TXDATFLITPEND <= 1'b0;
    TXDATFLITV <= 1'b1;
    TXDATFLIT <= flit[IF_DAT_W-1:0];
    TXDATFLITCHK <= chk[IF_DAT_CHK_W-1:0];
    if (txDatCredits > 0) txDatCredits--;
    txDatFlitsSent++;
    @(posedge CLK);
    TXDATFLITV <= 1'b0;
    txDatSem.put(1);
  endtask

  // Blocks until the channel may legally carry a flit: the direction is in RUN
  // (or draining, when called from the credit drain) and a credit is in hand.
  // The no-credit injection knob is the one way past the credit test, and it
  // exists so that a directed test can provoke linkCreditError.
  task automatic waitSendWindow(input chiGlobalsPkg::chiChannelE channel,
                                input bit allowDuringDrain);
    forever begin
      if (RESETn === 1'b1) begin
        if ((txLinkState == chiGlobalsPkg::LINK_RUN) ||
            (allowDuringDrain && (txLinkState == chiGlobalsPkg::LINK_DEACTIVATE))) begin
          if (injectSendWithoutCredit) break;
          case (channel)
            chiGlobalsPkg::CHI_CH_REQ: if (txReqCredits > 0) break;
            chiGlobalsPkg::CHI_CH_RSP: if (txRspCredits > 0) break;
            default:                   if (txDatCredits > 0) break;
          endcase
        end
      end
      @(posedge CLK);
    end
  endtask

  function automatic logic [chiGlobalsPkg::CHK_MAX_W-1:0] flitCheckFor(
      input chiGlobalsPkg::chiRawFlitT flit, input int unsigned flitWidth);
    logic [chiGlobalsPkg::CHK_MAX_W-1:0] chk;
    // The DUT computes even byte parity; the odd convention is available so a
    // directed test can show which one the design accepts.
    // See OPEN QUESTIONS Q17.
    chk = injectOddParity ? chiGlobalsPkg::flitCheckOdd(flit, flitWidth)
                          : chiGlobalsPkg::flitCheckEven(flit, flitWidth);
    if (injectParityError && (injectParityBit < chiGlobalsPkg::CHK_MAX_W))
      chk[injectParityBit] = ~chk[injectParityBit];
    return chk;
  endfunction

  //----------------------------------------------------------------------------
  // Credit drain
  //
  // On deactivation a transmitter must give back every credit it still holds,
  // and the only way to do that is an LCrdReturn flit on the channel that
  // granted it. An all-zero flit is exactly that on every channel, which is
  // why the drain works without depending on the field placement in
  // chiGlobalsPkg being right.
  //----------------------------------------------------------------------------

  task automatic txCreditDrainLoop();
    forever begin
      @(posedge CLK);
      if ((RESETn === 1'b1) &&
          (txLinkState == chiGlobalsPkg::LINK_DEACTIVATE)) begin
        if (useTxReq && (txReqCredits > 0))
          sendReqFlit(chiGlobalsPkg::lcrdReturnFlit(), 1'b1);
        else if (useTxRsp && (txRspCredits > 0))
          sendRspFlit(chiGlobalsPkg::lcrdReturnFlit(), 1'b1);
        else if (useTxDat && (txDatCredits > 0))
          sendDatFlit(chiGlobalsPkg::lcrdReturnFlit(), 1'b1);
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Receive accessors
  //----------------------------------------------------------------------------

  task automatic getReqFlit(output chiGlobalsPkg::chiRawFlitT flit);
    wait (rxReqQueue.size() > 0);
    flit = rxReqQueue.pop_front();
  endtask

  task automatic getRspFlit(output chiGlobalsPkg::chiRawFlitT flit);
    wait (rxRspQueue.size() > 0);
    flit = rxRspQueue.pop_front();
  endtask

  task automatic getDatFlit(output chiGlobalsPkg::chiRawFlitT flit);
    wait (rxDatQueue.size() > 0);
    flit = rxDatQueue.pop_front();
  endtask

  task automatic getSnpFlit(output chiGlobalsPkg::chiRawFlitT flit);
    wait (rxSnpQueue.size() > 0);
    flit = rxSnpQueue.pop_front();
  endtask

  function automatic int unsigned pendingRspCount();
    return rxRspQueue.size();
  endfunction

  function automatic int unsigned pendingDatCount();
    return rxDatQueue.size();
  endfunction

  function automatic int unsigned pendingSnpCount();
    return rxSnpQueue.size();
  endfunction

  function automatic int unsigned pendingReqCount();
    return rxReqQueue.size();
  endfunction

  //----------------------------------------------------------------------------
  // System coherency handshake
  //
  // The DUT returns SYSCOACK as a combinational copy of SYSCOREQ, so entry and
  // exit complete in the same cycle and no test can observe a latency here
  // [ASSUMPTION:4].
  //----------------------------------------------------------------------------

  task automatic sysCoEnter();
    if (!chiGlobalsPkg::nodeClassUsesSysCo(nodeClass)) return;
    @(posedge CLK);
    SYSCOREQ <= 1'b1;
    do @(posedge CLK); while (SYSCOACK !== 1'b1);
  endtask

  task automatic sysCoExit();
    if (!chiGlobalsPkg::nodeClassUsesSysCo(nodeClass)) return;
    @(posedge CLK);
    SYSCOREQ <= 1'b0;
    do @(posedge CLK); while (SYSCOACK !== 1'b0);
  endtask

  //----------------------------------------------------------------------------
  // Status, for the driver proxy and the end-of-test checks
  //----------------------------------------------------------------------------

  function automatic chiGlobalsPkg::chiLinkStateE txState();
    return txLinkState;
  endfunction

  function automatic chiGlobalsPkg::chiLinkStateE rxState();
    return rxLinkState;
  endfunction

  function automatic int unsigned heldCreditCount();
    return txReqCredits + txRspCredits + txDatCredits;
  endfunction

  function automatic int unsigned advertisedCreditCount();
    return rxReqCreditsOut + rxRspCreditsOut + rxDatCreditsOut + rxSnpCreditsOut;
  endfunction

  function automatic int unsigned queuedFlitCount();
    return rxReqQueue.size() + rxRspQueue.size() + rxDatQueue.size() +
           rxSnpQueue.size();
  endfunction

  task automatic waitClocks(input int unsigned cycles);
    repeat (cycles) @(posedge CLK);
  endtask
