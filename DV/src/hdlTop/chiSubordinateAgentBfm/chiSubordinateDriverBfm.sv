// Subordinate pin driver. SN-F and SN-I share one BFM. The node class is
// not a pin difference: both receive REQ and return RSP and DAT.
// TXREQ and TXSNP stay tied off. See OPEN QUESTIONS item 1.
// [ASSUMPTION:1] [TOP:snf] [TOP:sni]

`timescale 1ns/1ps

interface chiSubordinateDriverBfm (
  chi_if chiPort,
  input int unsigned nodeOrdinalIn,
  input bit portActiveIn
);
  import chiGlobalsPkg::*;
  localparam bit IS_REQUESTER = 1'b0;
  `include "chiLinkLayerBfm.svh"
  initial bindNode(nodeOrdinalIn, portActiveIn);
endinterface
