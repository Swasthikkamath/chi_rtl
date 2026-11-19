// Base test: builds the environment and owns the run-to-completion policy.
//
// Ending a run on this fabric needs care. The driver proxies never return:
// their routers and snoop handlers are forever loops, because a Requester must
// stay able to answer a snoop for as long as the fabric might send one. So the
// run cannot end by every process finishing. It ends on this test's objection,
// followed by a drain window long enough for whatever was in flight when the
// stimulus stopped to finish and be checked.
//
// A drain that is too short would report transactions as never completed when
// they were merely still in progress, so the window is generous and is
// overridable per test.
class chiBaseTest extends uvm_test;

  topEnvConfig cfg;
  topEnv       environment;

  virtual chiClkRstBfm clkRstBfm;

  // Cycles to let the fabric settle after the stimulus has finished.
  int unsigned drainCycles = 2000;

  // Hard ceiling, so a deadlock is reported as a failure rather than running
  // until the simulator is killed.
  time testTimeout = 2ms;

  `uvm_component_utils(chiBaseTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = topEnvConfig::type_id::create("cfg");
    cfg.initialise();
    configureEnv();

    uvm_config_db #(topEnvConfig)::set(this, "*", "topEnvConfig", cfg);

    if (!uvm_config_db #(virtual chiClkRstBfm)::get(this, "", "chiClkRstBfm",
                                                    clkRstBfm))
      `uvm_fatal(get_type_name(), "no chiClkRstBfm")

    environment = topEnv::type_id::create("environment", this);
  endfunction

  // Hook for a derived test to change the agent mix or the checking policy
  // before the environment is built.
  virtual function void configureEnv();
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("configuration:\n%s", cfg.chiCfg.convert2string()),
              UVM_LOW)
    `uvm_info(get_type_name(),
              $sformatf({"fabric: %0d nodes, %0d HN-F, data bus %0d bits, ",
                         "address %0d bits, lcrdDepth %0d, POS %0d entries"},
                        NUM_NODES, CHI_CFG.numHnf, CHI_CFG.dataW,
                        CHI_CFG.addrW, CHI_CFG.lcrdDepth, CHI_CFG.posEntries),
              UVM_LOW)
  endfunction

  // The sequence a derived test wants to run. Returning null means the test
  // only brings the links up.
  virtual function uvm_sequence_base testSequence();
    return null;
  endfunction

  task run_phase(uvm_phase phase);
    uvm_sequence_base seq_;

    phase.raise_objection(this, "chiBaseTest running");

    fork
      begin
        #testTimeout;
        `uvm_fatal(get_type_name(),
                   $sformatf("test did not finish within %0t", testTimeout))
      end
    join_none

    seq_ = testSequence();
    if (seq_ != null) begin
      `uvm_info(get_type_name(),
                $sformatf("starting %s", seq_.get_type_name()), UVM_LOW)
      seq_.start(environment.chiEnvironment.virtualSequencer);
      `uvm_info(get_type_name(), "stimulus complete", UVM_LOW)
    end else begin
      // Link bring-up only: long enough for both directions of every link to
      // walk STOP, ACTIVATE and RUN and exchange their credit allocation.
      clkRstBfm.waitCycles(200);
    end

    clkRstBfm.waitCycles(drainCycles);
    phase.drop_objection(this, "chiBaseTest finished");
  endtask
endclass
