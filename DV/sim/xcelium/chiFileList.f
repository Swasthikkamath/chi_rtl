// chiFileList.f
//
// Compile order for the CHI interconnect testbench.
//
// The DUT is not listed file by file here. It is pulled in through the
// repository's own filelist.f with -F, whose paths are relative to the file
// itself, so the RTL list stays owned by the design and this file never has to
// track a rename. CHI_RTL_ROOT is set by the Makefile and defaults to a
// sibling checkout.
//
// Order matters in exactly two places: chi_cfg_pkg must be compiled before
// chiGlobalsPkg, which the DUT list guarantees by coming first, and
// chiGlobalsPkg must be compiled before anything that imports it.

-F $CHI_RTL_ROOT/filelist.f

// Include search path for the shared link layer, which both driver BFMs
// include. Written in the +incdir+ form rather than -incdir so that the same
// list works under xrun and under the static front end used for elaboration
// checks. The RTL itself needs no include path [ASSUMPTION:21].
+incdir+$CHI_TB_ROOT/src/hdlTop/chiLink

// Testbench-owned configuration and protocol model, imported by both tops.
$CHI_TB_ROOT/src/globals/chiGlobalsPkg.sv

// hdlTop side: everything that touches a pin.
$CHI_TB_ROOT/src/hdlTop/chiInterface/chiClkRstBfm.sv
$CHI_TB_ROOT/src/hdlTop/chiRequesterAgentBfm/chiRequesterDriverBfm.sv
$CHI_TB_ROOT/src/hdlTop/chiSubordinateAgentBfm/chiSubordinateDriverBfm.sv
$CHI_TB_ROOT/src/hdlTop/chiMonitor/chiMonitorBfm.sv
$CHI_TB_ROOT/src/hdlTop/hdlTop.sv
