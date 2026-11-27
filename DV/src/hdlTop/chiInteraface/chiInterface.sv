`ifndef CHIINTERFACE_INCLUDED
`define CHIINTERFACE_INCLUDED

interface chiInterface #(
    parameter int REQ_FLIT_WIDTH = 256,
    parameter int RSP_FLIT_WIDTH = 128,
    parameter int SNP_FLIT_WIDTH = 256,
    parameter int DAT_FLIT_WIDTH = 128,
    parameter int NUM_RP_REQ = 1,
    parameter int NUM_RP_SNP = 1
)(input clk,input reset);
  timeunit 1ns;
  timeprecision 1ps;
  bit[3:0]qos;
  // Resource plane index widths
    localparam int REQ_RP_WIDTH = (NUM_RP_REQ <= 1) ? 1 : $clog2(NUM_RP_REQ);
    localparam int SNP_RP_WIDTH = (NUM_RP_SNP <= 1) ? 1 : $clog2(NUM_RP_SNP);

    // --------------------------------
    // Link activation signals
    // --------------------------------

    logic TXLINKACTIVEREQ;
    logic TXLINKACTIVEACK;

    logic RXLINKACTIVEREQ;
    logic RXLINKACTIVEACK;

    logic TXSACTIVE;
    logic RXSACTIVE;

    // System coherency signals
    logic SYSCOREQ;
    logic SYSCOACK;


    // --------------------------------
    // Transmitter side
    // --------------------------------

    // TX REQ
    logic                          TXREQFLITPEND;
    logic                          TXREQFLITV;
    logic [REQ_FLIT_WIDTH-1:0]     TXREQFLIT;
    logic [REQ_RP_WIDTH-1:0]       TXREQFLITRP;
    logic                          TXREQSHAREDCRD;
    logic [NUM_RP_REQ-1:0]         TXREQLCRDV;
    logic                          TXREQLCRDSHV;

    // TX RSP
    logic                          TXRSPFLITPEND;
    logic                          TXRSPFLITV;
    logic [RSP_FLIT_WIDTH-1:0]     TXRSPFLIT;
    logic                          TXRSPLCRDV;

    // TX SNP
    logic                          TXSNPFLITPEND;
    logic                          TXSNPFLITV;
    logic [SNP_FLIT_WIDTH-1:0]     TXSNPFLIT;
    logic [SNP_RP_WIDTH-1:0]       TXSNPFLITRP;
    logic                          TXSNPSHAREDCRD;
    logic [NUM_RP_SNP-1:0]         TXSNPLCRDV;
    logic                          TXSNPLCRDSHV;

    // TX DAT
    logic                          TXDATFLITPEND;
    logic                          TXDATFLITV;
    logic [DAT_FLIT_WIDTH-1:0]     TXDATFLIT;
    logic                          TXDATLCRDV;


    // --------------------------------
    // Receiver side
    // --------------------------------

    // RX REQ
    logic                          RXREQFLITPEND;
    logic                          RXREQFLITV;
    logic [REQ_FLIT_WIDTH-1:0]     RXREQFLIT;
    logic [REQ_RP_WIDTH-1:0]       RXREQFLITRP;
    logic                          RXREQSHAREDCRD;
    logic [NUM_RP_REQ-1:0]         RXREQLCRDV;
    logic                          RXREQLCRDSHV;

    // RX RSP
    logic                          RXRSPFLITPEND;
    logic                          RXRSPFLITV;
    logic [RSP_FLIT_WIDTH-1:0]     RXRSPFLIT;
    logic                          RXRSPLCRDV;

    // RX SNP
    logic                          RXSNPFLITPEND;
    logic                          RXSNPFLITV;
    logic [SNP_FLIT_WIDTH-1:0]     RXSNPFLIT;
    logic [SNP_RP_WIDTH-1:0]       RXSNPFLITRP;
    logic                          RXSNPSHAREDCRD;
    logic [NUM_RP_SNP-1:0]         RXSNPLCRDV;
    logic                          RXSNPLCRDSHV;

    // RX DAT
    logic                          RXDATFLITPEND;
    logic                          RXDATFLITV;
    logic [DAT_FLIT_WIDTH-1:0]     RXDATFLIT;
    logic                          RXDATLCRDV;

  modport chiRequestNodeDriverModport(input qos,input clk,input reset);
  modport chiRequestNodeMonitorModport(output qos,input clk,input reset);
  modport chiSubordinateNodeDriverModport(input qos,input clk,input reset);
  modport chiSubordinateNodeMonitorModport(output qos,input clk,input reset);
endinterface 

`endif 
