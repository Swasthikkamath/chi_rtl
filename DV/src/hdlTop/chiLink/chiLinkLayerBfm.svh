// Link layer shared by both driver BFMs. Included once so requester and
// subordinate ports cannot drift apart on credit or link-state rules.
// Pin names are the Issue H names. TX/RX are the external node's view.
// The receiver of a channel drives *LCRDV, so the node drives RX*LCRDV
// and only samples TX*LCRDV. See OPEN QUESTIONS items 1, 2 and 8.
// [SPEC:IHI0050H B14.2] [SPEC:IHI0050H B14.5] [ASSUMPTION:1] [ASSUMPTION:8]

  localparam int unsigned LCRD_CAP = CHI_CFG.lcrdDepth;

  bit portActive = 1'b0;
  int unsigned nodeOrdinal;
  // Written only by tasks. The clocked process samples them.
  bit txQuiesce = 1'b0;
  bit txLinkReleaseReq = 1'b0;

  bit txReqLocked;
  bit txRspLocked;
  bit txDatLocked;

  logic txLinkActiveReq;
  logic rxLinkActiveAck;
  logic sysCoReq;

  logic txReqFlitPend;
  logic txReqFlitV;
  chiFlitBitsT txReqFlit;
  logic [CHI_TB_MAX_FLIT_CHK_W-1:0] txReqFlitChk;
  bit txReqArm;
  bit txReqPendArmed;
  chiFlitBitsT txReqHolding;
  int unsigned txReqCredit;

  logic txRspFlitPend;
  logic txRspFlitV;
  chiFlitBitsT txRspFlit;
  logic [CHI_TB_MAX_FLIT_CHK_W-1:0] txRspFlitChk;
  bit txRspArm;
  bit txRspPendArmed;
  chiFlitBitsT txRspHolding;
  int unsigned txRspCredit;

  logic txDatFlitPend;
  logic txDatFlitV;
  chiFlitBitsT txDatFlit;
  logic [CHI_TB_MAX_FLIT_CHK_W-1:0] txDatFlitChk;
  bit txDatArm;
  bit txDatPendArmed;
  chiFlitBitsT txDatHolding;
  int unsigned txDatCredit;

  logic rxReqLcrdv;
  logic rxRspLcrdv;
  logic rxDatLcrdv;
  logic rxSnpLcrdv;
  int unsigned rxReqOutstanding;
  int unsigned rxRspOutstanding;
  int unsigned rxDatOutstanding;
  int unsigned rxSnpOutstanding;

  // Node-owned pins. 1-bit *CHK, CLK, RESETn, and both SACTIVE pins are
  // DUT outputs and are intentionally not driven here. [ASSUMPTION:2]
  generate
    if (IS_REQUESTER) begin : requesterDrive
      assign chiPort.TXREQFLITPEND = portActive ? txReqFlitPend : 1'b0;
      assign chiPort.TXREQFLITV = portActive ? txReqFlitV : 1'b0;
      assign chiPort.TXREQFLIT = txReqFlit[$bits(chiPort.TXREQFLIT)-1:0];
      assign chiPort.TXREQFLITCHK =
        txReqFlitChk[$bits(chiPort.TXREQFLITCHK)-1:0];
      assign chiPort.RXREQLCRDV = 1'b0;
      assign chiPort.RXSNPLCRDV = portActive ? rxSnpLcrdv : 1'b0;
      assign chiPort.SYSCOREQ = portActive ? sysCoReq : 1'b0;
    end else begin : subordinateDrive
      assign chiPort.TXREQFLITPEND = 1'b0;
      assign chiPort.TXREQFLITV = 1'b0;
      assign chiPort.TXREQFLIT = '0;
      assign chiPort.TXREQFLITCHK = '0;
      assign chiPort.RXREQLCRDV = portActive ? rxReqLcrdv : 1'b0;
      assign chiPort.RXSNPLCRDV = 1'b0;
      assign chiPort.SYSCOREQ = 1'b0;
    end
  endgenerate

  assign chiPort.TXRSPFLITPEND = portActive ? txRspFlitPend : 1'b0;
  assign chiPort.TXRSPFLITV = portActive ? txRspFlitV : 1'b0;
  assign chiPort.TXRSPFLIT = txRspFlit[$bits(chiPort.TXRSPFLIT)-1:0];
  assign chiPort.TXRSPFLITCHK = txRspFlitChk[$bits(chiPort.TXRSPFLITCHK)-1:0];
  assign chiPort.TXDATFLITPEND = portActive ? txDatFlitPend : 1'b0;
  assign chiPort.TXDATFLITV = portActive ? txDatFlitV : 1'b0;
  assign chiPort.TXDATFLIT = txDatFlit[$bits(chiPort.TXDATFLIT)-1:0];
  assign chiPort.TXDATFLITCHK = txDatFlitChk[$bits(chiPort.TXDATFLITCHK)-1:0];
  // [ASSUMPTION:1] No external node transmits SNP.
  assign chiPort.TXSNPFLITPEND = 1'b0;
  assign chiPort.TXSNPFLITV = 1'b0;
  assign chiPort.TXSNPFLIT = '0;
  assign chiPort.TXSNPFLITCHK = '0;
  assign chiPort.TXLINKACTIVEREQ = portActive ? txLinkActiveReq : 1'b0;
  assign chiPort.RXLINKACTIVEACK = portActive ? rxLinkActiveAck : 1'b0;
  assign chiPort.RXRSPLCRDV = portActive ? rxRspLcrdv : 1'b0;
  assign chiPort.RXDATLCRDV = portActive ? rxDatLcrdv : 1'b0;

  task automatic bindNode(input int unsigned ordinal, input bit active);
    nodeOrdinal = ordinal;
    portActive = active;
  endtask

  task automatic chiSetSysCoReq(input logic value);
    sysCoReq = value;
  endtask

  function automatic bit chiTxLinkRun();
    return txLinkActiveReq && (chiPort.TXLINKACTIVEACK === 1'b1);
  endfunction

  function automatic bit chiRxLinkRun();
    return rxLinkActiveAck && (chiPort.RXLINKACTIVEREQ === 1'b1);
  endfunction

  task automatic chiSendReq(input chiReqFlitT flit, input bit creditReturn);
    if (!IS_REQUESTER)
      return;
    while (txQuiesce && !creditReturn)
      @(posedge chiPort.CLK);
    while (txReqLocked)
      @(posedge chiPort.CLK);
    txReqLocked = 1'b1;
    @(posedge chiPort.CLK);
    txReqHolding = chiPackReqFlit(CHI_CFG, flit);
    txReqArm = 1'b1;
    @(posedge chiPort.CLK iff (txReqArm == 1'b0));
    txReqLocked = 1'b0;
  endtask

  task automatic chiSendRsp(input chiRspFlitT flit, input bit creditReturn);
    while (txQuiesce && !creditReturn)
      @(posedge chiPort.CLK);
    while (txRspLocked)
      @(posedge chiPort.CLK);
    txRspLocked = 1'b1;
    @(posedge chiPort.CLK);
    txRspHolding = chiPackRspFlit(CHI_CFG, flit);
    txRspArm = 1'b1;
    @(posedge chiPort.CLK iff (txRspArm == 1'b0));
    txRspLocked = 1'b0;
  endtask

  task automatic chiSendDat(input chiDatFlitT flit, input bit creditReturn);
    while (txQuiesce && !creditReturn)
      @(posedge chiPort.CLK);
    while (txDatLocked)
      @(posedge chiPort.CLK);
    txDatLocked = 1'b1;
    @(posedge chiPort.CLK);
    txDatHolding = chiPackDatFlit(CHI_CFG, flit);
    txDatArm = 1'b1;
    @(posedge chiPort.CLK iff (txDatArm == 1'b0));
    txDatLocked = 1'b0;
  endtask

  task automatic chiDrainReqCredits();
    chiReqFlitT creditReturn;
    if (!IS_REQUESTER)
      return;
    creditReturn = chiZeroReqFlit();
    creditReturn.opcode = CHI_REQ_LCRD_RETURN;
    forever begin
      @(posedge chiPort.CLK);
      if (txReqCredit == 0)
        break;
      chiSendReq(creditReturn, 1'b1);
    end
  endtask

  task automatic chiDrainRspCredits();
    chiRspFlitT creditReturn;
    creditReturn = chiZeroRspFlit();
    creditReturn.opcode = CHI_RSP_LCRD_RETURN;
    forever begin
      @(posedge chiPort.CLK);
      if (txRspCredit == 0)
        break;
      chiSendRsp(creditReturn, 1'b1);
    end
  endtask

  task automatic chiDrainDatCredits();
    chiDatFlitT creditReturn;
    creditReturn = chiZeroDatFlit();
    creditReturn.opcode = CHI_DAT_LCRD_RETURN;
    forever begin
      @(posedge chiPort.CLK);
      if (txDatCredit == 0)
        break;
      chiSendDat(creditReturn, 1'b1);
    end
  endtask

  // Drop our TX link after unused credits are returned. The RX ack falls
  // only once the DUT drops RXLINKACTIVEREQ and every granted credit is back.
  task automatic chiLinkDeactivate();
    txQuiesce = 1'b1;
    chiDrainReqCredits();
    chiDrainRspCredits();
    chiDrainDatCredits();
    txLinkReleaseReq = 1'b1;
    @(posedge chiPort.CLK iff (chiPort.TXLINKACTIVEACK === 1'b0));
    @(posedge chiPort.CLK iff ((chiPort.RXLINKACTIVEREQ === 1'b0)
      && (rxLinkActiveAck === 1'b0)));
  endtask

  task automatic chiWaitRxReq(output chiReqFlitT flit);
    chiFlitBitsT bits;
    @(posedge chiPort.CLK iff (chiPort.RESETn && chiPort.RXREQFLITV));
    bits = '0;
    bits[$bits(chiPort.RXREQFLIT)-1:0] = chiPort.RXREQFLIT;
    flit = chiUnpackReqFlit(CHI_CFG, bits);
  endtask

  task automatic chiWaitRxRsp(output chiRspFlitT flit);
    chiFlitBitsT bits;
    @(posedge chiPort.CLK iff (chiPort.RESETn && chiPort.RXRSPFLITV));
    bits = '0;
    bits[$bits(chiPort.RXRSPFLIT)-1:0] = chiPort.RXRSPFLIT;
    flit = chiUnpackRspFlit(CHI_CFG, bits);
  endtask

  task automatic chiWaitRxDat(output chiDatFlitT flit);
    chiFlitBitsT bits;
    @(posedge chiPort.CLK iff (chiPort.RESETn && chiPort.RXDATFLITV));
    bits = '0;
    bits[$bits(chiPort.RXDATFLIT)-1:0] = chiPort.RXDATFLIT;
    flit = chiUnpackDatFlit(CHI_CFG, bits);
  endtask

  task automatic chiWaitRxSnp(output chiSnpFlitT flit);
    chiFlitBitsT bits;
    @(posedge chiPort.CLK iff (chiPort.RESETn && chiPort.RXSNPFLITV));
    bits = '0;
    bits[$bits(chiPort.RXSNPFLIT)-1:0] = chiPort.RXSNPFLIT;
    flit = chiUnpackSnpFlit(CHI_CFG, bits);
  endtask

  always @(posedge chiPort.CLK or negedge chiPort.RESETn) begin
    int unsigned nextReqCredit;
    int unsigned nextRspCredit;
    int unsigned nextDatCredit;
    int unsigned nextRxReq;
    int unsigned nextRxRsp;
    int unsigned nextRxDat;
    int unsigned nextRxSnp;
    if (!chiPort.RESETn) begin
      txLinkActiveReq <= 1'b0;
      rxLinkActiveAck <= 1'b0;
      sysCoReq <= 1'b0;
      txReqFlitPend <= 1'b0;
      txReqFlitV <= 1'b0;
      txReqFlit <= '0;
      txReqFlitChk <= '0;
      txReqArm <= 1'b0;
      txReqPendArmed <= 1'b0;
      txReqCredit <= 0;
      txRspFlitPend <= 1'b0;
      txRspFlitV <= 1'b0;
      txRspFlit <= '0;
      txRspFlitChk <= '0;
      txRspArm <= 1'b0;
      txRspPendArmed <= 1'b0;
      txRspCredit <= 0;
      txDatFlitPend <= 1'b0;
      txDatFlitV <= 1'b0;
      txDatFlit <= '0;
      txDatFlitChk <= '0;
      txDatArm <= 1'b0;
      txDatPendArmed <= 1'b0;
      txDatCredit <= 0;
      rxReqLcrdv <= 1'b0;
      rxRspLcrdv <= 1'b0;
      rxDatLcrdv <= 1'b0;
      rxSnpLcrdv <= 1'b0;
      rxReqOutstanding <= 0;
      rxRspOutstanding <= 0;
      rxDatOutstanding <= 0;
      rxSnpOutstanding <= 0;
    end else if (!portActive) begin
      txLinkActiveReq <= 1'b0;
      rxLinkActiveAck <= 1'b0;
    end else begin
      // [ASSUMPTION:8] Acknowledge the DUT's TX link on the clock after
      // RXLINKACTIVEREQ rises. Hold the ack through credit return.
      if (chiPort.RXLINKACTIVEREQ === 1'b1)
        rxLinkActiveAck <= 1'b1;
      else if ((rxReqOutstanding == 0) && (rxRspOutstanding == 0)
          && (rxDatOutstanding == 0) && (rxSnpOutstanding == 0))
        rxLinkActiveAck <= 1'b0;

      if (txLinkReleaseReq)
        txLinkActiveReq <= 1'b0;
      else
        txLinkActiveReq <= 1'b1;

      nextReqCredit = txReqCredit;
      nextRspCredit = txRspCredit;
      nextDatCredit = txDatCredit;
      if (chiPort.TXREQLCRDV === 1'b1)
        nextReqCredit++;
      if (chiPort.TXRSPLCRDV === 1'b1)
        nextRspCredit++;
      if (chiPort.TXDATLCRDV === 1'b1)
        nextDatCredit++;

      txReqFlitV <= 1'b0;
      txRspFlitV <= 1'b0;
      txDatFlitV <= 1'b0;

      if (IS_REQUESTER && txReqArm && !txReqPendArmed && (nextReqCredit > 0)
          && txLinkActiveReq && (chiPort.TXLINKACTIVEACK === 1'b1)) begin
        txReqFlitPend <= 1'b1;
        txReqPendArmed <= 1'b1;
      end else if (txReqPendArmed) begin
        txReqFlitPend <= 1'b0;
        txReqFlitV <= 1'b1;
        txReqFlit <= txReqHolding;
        txReqFlitChk <= chiOddByteParity(txReqHolding, chiReqFlitWidth(CHI_CFG));
        nextReqCredit--;
        txReqPendArmed <= 1'b0;
        txReqArm <= 1'b0;
      end else begin
        txReqFlitPend <= 1'b0;
      end

      if (txRspArm && !txRspPendArmed && (nextRspCredit > 0)
          && txLinkActiveReq && (chiPort.TXLINKACTIVEACK === 1'b1)) begin
        txRspFlitPend <= 1'b1;
        txRspPendArmed <= 1'b1;
      end else if (txRspPendArmed) begin
        txRspFlitPend <= 1'b0;
        txRspFlitV <= 1'b1;
        txRspFlit <= txRspHolding;
        txRspFlitChk <= chiOddByteParity(txRspHolding, chiRspFlitWidth(CHI_CFG));
        nextRspCredit--;
        txRspPendArmed <= 1'b0;
        txRspArm <= 1'b0;
      end else begin
        txRspFlitPend <= 1'b0;
      end

      if (txDatArm && !txDatPendArmed && (nextDatCredit > 0)
          && txLinkActiveReq && (chiPort.TXLINKACTIVEACK === 1'b1)) begin
        txDatFlitPend <= 1'b1;
        txDatPendArmed <= 1'b1;
      end else if (txDatPendArmed) begin
        txDatFlitPend <= 1'b0;
        txDatFlitV <= 1'b1;
        txDatFlit <= txDatHolding;
        txDatFlitChk <= chiOddByteParity(txDatHolding, chiDatFlitWidth(CHI_CFG));
        nextDatCredit--;
        txDatPendArmed <= 1'b0;
        txDatArm <= 1'b0;
      end else begin
        txDatFlitPend <= 1'b0;
      end

      txReqCredit <= nextReqCredit;
      txRspCredit <= nextRspCredit;
      txDatCredit <= nextDatCredit;

      nextRxReq = rxReqOutstanding;
      nextRxRsp = rxRspOutstanding;
      nextRxDat = rxDatOutstanding;
      nextRxSnp = rxSnpOutstanding;
      if ((chiPort.RXREQFLITV === 1'b1) && (nextRxReq > 0))
        nextRxReq--;
      if ((chiPort.RXRSPFLITV === 1'b1) && (nextRxRsp > 0))
        nextRxRsp--;
      if ((chiPort.RXDATFLITV === 1'b1) && (nextRxDat > 0))
        nextRxDat--;
      if ((chiPort.RXSNPFLITV === 1'b1) && (nextRxSnp > 0))
        nextRxSnp--;

      // Grants start once our ack is high. The cap is lcrdDepth.
      if (rxLinkActiveAck && (chiPort.RXLINKACTIVEREQ === 1'b1)) begin
        if (!IS_REQUESTER && (nextRxReq < LCRD_CAP)) begin
          rxReqLcrdv <= 1'b1;
          nextRxReq++;
        end else begin
          rxReqLcrdv <= 1'b0;
        end
        if (nextRxRsp < LCRD_CAP) begin
          rxRspLcrdv <= 1'b1;
          nextRxRsp++;
        end else begin
          rxRspLcrdv <= 1'b0;
        end
        if (nextRxDat < LCRD_CAP) begin
          rxDatLcrdv <= 1'b1;
          nextRxDat++;
        end else begin
          rxDatLcrdv <= 1'b0;
        end
        if (IS_REQUESTER && (nextRxSnp < LCRD_CAP)) begin
          rxSnpLcrdv <= 1'b1;
          nextRxSnp++;
        end else begin
          rxSnpLcrdv <= 1'b0;
        end
      end else begin
        rxReqLcrdv <= 1'b0;
        rxRspLcrdv <= 1'b0;
        rxDatLcrdv <= 1'b0;
        rxSnpLcrdv <= 1'b0;
      end
      rxReqOutstanding <= nextRxReq;
      rxRspOutstanding <= nextRxRsp;
      rxDatOutstanding <= nextRxDat;
      rxSnpOutstanding <= nextRxSnp;
    end
  end
