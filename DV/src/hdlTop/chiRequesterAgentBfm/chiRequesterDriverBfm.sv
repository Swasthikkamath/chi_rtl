// Requester pin driver. The class in hvlTop never touches a pin; it calls
// these tasks through a virtual interface. Link behaviour is included from
// chiLinkLayerBfm.svh so it stays identical to the subordinate driver.
// [ASSUMPTION:1] [TOP:rnf] [TOP:rnd] [TOP:rni]

`timescale 1ns/1ps

interface chiRequesterDriverBfm (
  chi_if chiPort,
  input int unsigned nodeOrdinalIn,
  input bit portActiveIn
);
  import chiGlobalsPkg::*;
  localparam bit IS_REQUESTER = 1'b1;
  `include "chiLinkLayerBfm.svh"
  // Applied inside the BFM so the parent does not call through a
  // generate index. A sentinel is connected with portActiveIn 0.
  initial bindNode(nodeOrdinalIn, portActiveIn);
endinterface
