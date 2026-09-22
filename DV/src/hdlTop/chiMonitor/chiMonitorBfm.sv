// Passive observer of one chi_if plus that ordinal's link status.
// It never drives a pin. The HVL monitor proxy blocks in the wait tasks.
// TXSACTIVE is sampled only. The spec makes it a node output; the DUT
// drives it. See OPEN QUESTIONS item 2.
// [SPEC:IHI0050H B14.7.2] [ASSUMPTION:2] [TOP:linkUp]

`timescale 1ns/1ps

interface chiMonitorBfm (
  chi_if chiPort,
  input logic linkUp,
  input logic linkParityError,
  input logic linkCreditError,
  input int unsigned nodeOrdinalIn,
  input bit portActiveIn
);
  import chiGlobalsPkg::*;

  bit portActive = 1'b0;
  int unsigned nodeOrdinal;
  // Sticky record of the known SACTIVE deviation, for the scoreboard.
  bit knownTxSactiveDeviation = 1'b1;
  logic txSactiveSample;
  logic rxSactiveSample;
  chiLinkStateE txLinkState;
  chiLinkStateE rxLinkState;

  chiReqFlitT txReqQ[$];
  chiRspFlitT txRspQ[$];
  chiDatFlitT txDatQ[$];
  chiReqFlitT rxReqQ[$];
  chiRspFlitT rxRspQ[$];
  chiDatFlitT rxDatQ[$];
  chiSnpFlitT rxSnpQ[$];

  task automatic bindNode(input int unsigned ordinal, input bit active);
    nodeOrdinal = ordinal;
    portActive = active;
  endtask

  initial bindNode(nodeOrdinalIn, portActiveIn);

  always @(posedge chiPort.CLK or negedge chiPort.RESETn) begin
    chiFlitBitsT bits;
    if (!chiPort.RESETn) begin
      txSactiveSample <= 1'b0;
      rxSactiveSample <= 1'b0;
      txLinkState <= CHI_LINK_STATE_STOP;
      rxLinkState <= CHI_LINK_STATE_STOP;
    end else begin
      txSactiveSample <= chiPort.TXSACTIVE;
      rxSactiveSample <= chiPort.RXSACTIVE;
      txLinkState <= chiEncodeLinkState(
        chiPort.TXLINKACTIVEREQ, chiPort.TXLINKACTIVEACK);
      rxLinkState <= chiEncodeLinkState(
        chiPort.RXLINKACTIVEREQ, chiPort.RXLINKACTIVEACK);
      if (chiPort.TXREQFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.TXREQFLIT)-1:0] = chiPort.TXREQFLIT;
        txReqQ.push_back(chiUnpackReqFlit(CHI_CFG, bits));
      end
      if (chiPort.TXRSPFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.TXRSPFLIT)-1:0] = chiPort.TXRSPFLIT;
        txRspQ.push_back(chiUnpackRspFlit(CHI_CFG, bits));
      end
      if (chiPort.TXDATFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.TXDATFLIT)-1:0] = chiPort.TXDATFLIT;
        txDatQ.push_back(chiUnpackDatFlit(CHI_CFG, bits));
      end
      if (chiPort.RXREQFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.RXREQFLIT)-1:0] = chiPort.RXREQFLIT;
        rxReqQ.push_back(chiUnpackReqFlit(CHI_CFG, bits));
      end
      if (chiPort.RXRSPFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.RXRSPFLIT)-1:0] = chiPort.RXRSPFLIT;
        rxRspQ.push_back(chiUnpackRspFlit(CHI_CFG, bits));
      end
      if (chiPort.RXDATFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.RXDATFLIT)-1:0] = chiPort.RXDATFLIT;
        rxDatQ.push_back(chiUnpackDatFlit(CHI_CFG, bits));
      end
      if (chiPort.RXSNPFLITV === 1'b1) begin
        bits = '0;
        bits[$bits(chiPort.RXSNPFLIT)-1:0] = chiPort.RXSNPFLIT;
        rxSnpQ.push_back(chiUnpackSnpFlit(CHI_CFG, bits));
      end
    end
  end

  task automatic chiGetTxReq(output chiReqFlitT flit);
    wait (txReqQ.size() > 0);
    flit = txReqQ.pop_front();
  endtask

  task automatic chiGetTxRsp(output chiRspFlitT flit);
    wait (txRspQ.size() > 0);
    flit = txRspQ.pop_front();
  endtask

  task automatic chiGetTxDat(output chiDatFlitT flit);
    wait (txDatQ.size() > 0);
    flit = txDatQ.pop_front();
  endtask

  task automatic chiGetRxReq(output chiReqFlitT flit);
    wait (rxReqQ.size() > 0);
    flit = rxReqQ.pop_front();
  endtask

  task automatic chiGetRxRsp(output chiRspFlitT flit);
    wait (rxRspQ.size() > 0);
    flit = rxRspQ.pop_front();
  endtask

  task automatic chiGetRxDat(output chiDatFlitT flit);
    wait (rxDatQ.size() > 0);
    flit = rxDatQ.pop_front();
  endtask

  task automatic chiGetRxSnp(output chiSnpFlitT flit);
    wait (rxSnpQ.size() > 0);
    flit = rxSnpQ.pop_front();
  endtask
endinterface
