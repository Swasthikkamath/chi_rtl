`ifndef CHIVIRTUALSEQUENCEPKG_INCLUDED
`define CHIVIRTUALSEQUENCEPKG_INCLUDED

package chiVirtualSequencePkg;
  `include "uvm_macros.svh"
  import uvm_pkg::*;
  import chiGlobalsPkg::*;
  import requestNodeSequencePkg::*;
  import subordinateNodeSequencePkg::*;
  import chiEnvPkg::*;

  `include "chiVirtualBaseSequence.sv"

endpackage

`endif 
