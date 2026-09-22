// A test of the testbench, not of the DUT.
//
// Every other test passes when no model complains, which is only worth
// something if a model would have complained had the data been wrong. So
// this one corrupts read data at a Subordinate while leaving RespErr at OK,
// which is the one failure no protocol check can catch: every flit is legal
// and only the value is wrong. The end-to-end image in topMemoryModel is
// the only thing that can see it.
//
// A test that expects a failure cannot simply let it through, so the
// mismatch reports are demoted to UVM_INFO and counted. Seeing none is the
// failure here: it means the comparison never ran, or ran against nothing,
// and every clean run of every other test would then be worth nothing
// either. [SPEC:IHI0050H B9.4 Error response]

// Only the data-mismatch reports are demoted. A poison count, an
// outstanding transaction, or any other complaint from the same model is
// left alone, because this test is not expecting those.
class chiCorruptCatcher extends uvm_report_catcher;
  int unsigned caught;

  function new(string name = "chiCorruptCatcher");
    super.new(name);
    caught = 0;
  endfunction

  function action_e catch();
    if (get_severity() != UVM_ERROR)
      return THROW;
    if (get_id() != "topMemoryModel")
      return THROW;
    // Both images report a mismatch with that word in the message: the one
    // built from Subordinate writes and the end-to-end one.
    if (!uvm_is_match("*mismatch*", get_message())
        && !uvm_is_match("*but the last write seen*", get_message()))
      return THROW;
    caught++;
    set_severity(UVM_INFO);
    set_verbosity(UVM_LOW);
    return THROW;
  endfunction
endclass

class chiDataCorruptTest extends chiBaseTest;
  chiCorruptCatcher catcher;

  `uvm_component_utils(chiDataCorruptTest)

  function new(string name = "chiDataCorruptTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    catcher = new("chiCorruptCatcher");
    uvm_report_cb::add(null, catcher);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_CORRUPT);
  endtask

  // check_phase, not the end of chiRun: the comparison happens as the data
  // beat is observed, and the last beat may not have been sampled yet when
  // the sequence returns.
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (catcher.caught == 0)
      `uvm_error("chiDataCorruptTest",
        {"read data was corrupted at a Subordinate and no model objected. ",
         "The data comparison is not running, so a clean run proves nothing"})
    else
      `uvm_info("chiDataCorruptTest",
        $sformatf("the data comparison caught the corruption %0d times, as intended",
                  catcher.caught), UVM_LOW)
  endfunction

  function void final_phase(uvm_phase phase);
    super.final_phase(phase);
    uvm_report_cb::delete(null, catcher);
  endfunction
endclass
