// Tests and the virtual sequence. uvm_pkg is re-exported. hvlTop also
// imports uvm_pkg directly, because slang does not honour that export.

package chiTestPkg;
  import uvm_pkg::*;
  export uvm_pkg::*;
  import chiGlobalsPkg::*;
  import chiRequesterPkg::*;
  import chiSubordinatePkg::*;
  import topEnvPkg::*;
  `include "uvm_macros.svh"

  `include "chiVirtualSeq.sv"
  `include "chiBaseTest.sv"
  `include "chiLinkBringUpTest.sv"
  `include "chiCoherentTrafficTest.sv"
  `include "chiSharedLineTest.sv"
  `include "chiRetryStressTest.sv"
  `include "chiPassiveAgentTest.sv"
  `include "chiRndReadTest.sv"
  `include "chiAtomicTest.sv"
  `include "chiDvmTest.sv"
  `include "chiStashTest.sv"
  `include "chiExclusiveTest.sv"
  `include "chiCmoTest.sv"
  `include "chiWriteZeroTest.sv"
  `include "chiOrderTest.sv"
  `include "chiRespErrTest.sv"
  `include "chiPoisonTest.sv"
  `include "chiMteTest.sv"
  `include "chiPbhaTest.sv"
  `include "chiMpamTest.sv"
  `include "chiMultiReqTest.sv"
  `include "chiParityTest.sv"
  `include "chiCreditErrorTest.sv"
  `include "chiUnmappedTest.sv"
  `include "chiDctTest.sv"
  `include "chiDmtTest.sv"
  `include "chiDwtTest.sv"
endpackage
