// chiFileList.f
//
// Compile order for the CHI interconnect testbench.
//
// The DUT is not listed file by file here. The design's own filelist.f stays
// the source of truth for what the DUT is made of, so a rename there never
// has to be tracked here. What this list reads is the sanitised copy the
// Makefile derives from it each build: '#' comments rewritten, paths made
// absolute, lint harnesses dropped, and the assertion bind files kept or
// dropped by SVA. CHI_DUT_FILELIST names that copy, and can be pointed at an
// explicit list instead. See OPEN QUESTIONS Q21.
//
// Order matters in exactly two places: chi_cfg_pkg must be compiled before
// chiGlobalsPkg, which the DUT list guarantees by coming first, and
// chiGlobalsPkg must be compiled before anything that imports it.

-F $CHI_DUT_FILELIST

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

// Agents. hvlTop, which imports the test package, is added with the tests.
// Each include path covers the classes that package pulls in.
+incdir+$CHI_TB_ROOT/src/hvlTop/chiRequester
$CHI_TB_ROOT/src/hvlTop/chiRequester/chiRequesterPkg.sv
+incdir+$CHI_TB_ROOT/src/hvlTop/chiSubordinate
$CHI_TB_ROOT/src/hvlTop/chiSubordinate/chiSubordinatePkg.sv

// Integration environment, tests, and the HVL top. hvlTop imports only
// chiTestPkg, which re-exports uvm_pkg so run_test is visible.
+incdir+$CHI_TB_ROOT/src/hvlTop/topEnv
$CHI_TB_ROOT/src/hvlTop/topEnv/topEnvPkg.sv
+incdir+$CHI_TB_ROOT/src/hvlTop/test
$CHI_TB_ROOT/src/hvlTop/test/chiTestPkg.sv
$CHI_TB_ROOT/src/hvlTop/hvlTop.sv
