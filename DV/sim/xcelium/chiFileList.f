// Paths are relative to this file. Invoke xrun with -F so they resolve
// here, not from the launch directory.
// [ASSUMPTION:9] The DUT list is an argument file. -F makes its own
// paths resolve from the chi_rtl directory. Do not `include it.
// +incdir+ is accepted by xrun and by Verilator. It names the directory
// that holds chiLinkLayerBfm.svh.

+incdir+../../src/hdlTop/chiLink
+incdir+../../src/hdlTop

-F ../../../chi_rtl/filelist.f

../../src/globals/chiGlobalsPkg.sv
../../src/hdlTop/chiInterface/chiClkRstBfm.sv
../../src/hdlTop/chiRequesterAgentBfm/chiRequesterDriverBfm.sv
../../src/hdlTop/chiSubordinateAgentBfm/chiSubordinateDriverBfm.sv
../../src/hdlTop/chiMonitor/chiMonitorBfm.sv
../../src/hdlTop/hdlTop.sv
