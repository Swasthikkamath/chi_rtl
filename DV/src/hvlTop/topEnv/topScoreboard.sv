//==============================================================================
// topScoreboard
//
// The scoreboard owns no check logic of its own. It is the junction between
// the boundary and the four reference models [ASSUMPTION:18]:
//
//   - every monitor proxy's raw flit sample stream lands on one analysis imp
//     here and is fanned out to the lifecycle, directory and memory models;
//   - every link sample stream lands on the other imp and feeds the link
//     model;
//   - at extract_phase it drains whatever the proxies had not consumed when
//     run_phase ended, so the last flits of the test are still checked.
//
// Why the raw sample stream and not the per-channel unpacked ports: the
// unpacked ports drop the node ordinal, the sample time and the
// L-Credit-return flag, and the models need all three. The proxies therefore
// export the chiFlitSampleT exactly as the monitor BFM queued it, and this
// component is the only subscriber.
//
// Why the drain exists: a monitor proxy forwards samples from a forever loop
// that run_phase kills wherever it happens to be when the test's last
// objection drops. Samples queued but not yet forwarded would otherwise be
// silently lost — and for the memory model a lost write is a fabricated
// provenance error on a later read. extract_phase runs after every run_phase
// process is dead and before any check_phase runs, so draining there is both
// safe (no concurrent queue access) and complete (nothing is sampled after
// it). A sample is popped from the BFM queue exactly once, by the proxy or by
// the drain, so the two paths never double-count.
//
// The models are children of this component, so their check_phase runs
// (bottom-up) after the drain and before this component's own check_phase;
// each model reports through its own UVM messages and summary.
//==============================================================================

`uvm_analysis_imp_decl(_flit)
`uvm_analysis_imp_decl(_link)

class topScoreboard extends uvm_scoreboard;

  topEnvConfig cfg;

  topLinkModel      linkModel;
  topLifecycleModel lifecycleModel;
  topDirectoryModel directoryModel;
  topMemoryModel    memoryModel;

  // One imp per sample kind for the whole bench: every agent's monitor proxy
  // connects its flitSamplePort to flitImp and its linkPort to linkImp.
  uvm_analysis_imp_flit#(chiGlobalsPkg::chiFlitSampleT, topScoreboard) flitImp;
  uvm_analysis_imp_link#(chiGlobalsPkg::chiLinkSampleT, topScoreboard) linkImp;

  // Monitor BFM handles, one per external port ordinal, fetched so that
  // extract_phase can drain the queues directly.
  virtual chiMonitorBfm monBfm[int unsigned];

  int unsigned flitSampleCount;
  int unsigned linkSampleCount;
  int unsigned drainedFlitCount;
  int unsigned drainedLinkCount;

  `uvm_component_utils(topScoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    flitSampleCount = 0;
    linkSampleCount = 0;
    drainedFlitCount = 0;
    drainedLinkCount = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(topEnvConfig)::get(this, "", "topEnvConfig", cfg))
      `uvm_fatal("SCB/CFG", "config_db get failed for key topEnvConfig")

    flitImp = new("flitImp", this);
    linkImp = new("linkImp", this);

    linkModel = topLinkModel::type_id::create("linkModel", this);
    lifecycleModel = topLifecycleModel::type_id::create("lifecycleModel", this);
    directoryModel = topDirectoryModel::type_id::create("directoryModel", this);
    memoryModel = topMemoryModel::type_id::create("memoryModel", this);
    linkModel.cfg = cfg;
    lifecycleModel.cfg = cfg;
    directoryModel.cfg = cfg;
    memoryModel.cfg = cfg;

    for (int unsigned ord = 0; ord < chiGlobalsPkg::OFF_HNF; ord++) begin
      if (!uvm_config_db#(virtual chiMonitorBfm)::get(this, "",
            chiGlobalsPkg::monitorBfmKey(ord), monBfm[ord]))
        `uvm_fatal("SCB/BFM", $sformatf(
          "no monitor BFM published for node ordinal %0d", ord))
    end
  endfunction

  //--------------------------------------------------------------------------
  // Sample distribution
  //--------------------------------------------------------------------------

  function void write_flit(input chiGlobalsPkg::chiFlitSampleT sample);
    flitSampleCount++;
    lifecycleModel.noteFlit(sample);
    directoryModel.noteFlit(sample);
    memoryModel.noteFlit(sample);
  endfunction

  function void write_link(input chiGlobalsPkg::chiLinkSampleT sample);
    linkSampleCount++;
    linkModel.noteLink(sample);
  endfunction

  //--------------------------------------------------------------------------
  // End-of-test drain
  //
  // Forwarded samples were already popped by the proxies; what remains in the
  // queues at this point was never seen by any model. Feeding it through the
  // same write functions keeps the counting honest.
  //--------------------------------------------------------------------------

  function void extract_phase(uvm_phase phase);
    chiGlobalsPkg::chiFlitSampleT flit;
    chiGlobalsPkg::chiLinkSampleT link;
    super.extract_phase(phase);
    foreach (monBfm[ord]) begin
      while (monBfm[ord].tryFlitSample(flit)) begin
        drainedFlitCount++;
        write_flit(flit);
      end
      while (monBfm[ord].tryLinkSample(link)) begin
        drainedLinkCount++;
        write_link(link);
      end
    end
    if ((drainedFlitCount > 0) || (drainedLinkCount > 0))
      `uvm_info("SCB/DRAIN", $sformatf(
        "drained %0d flit and %0d link samples left unforwarded when run_phase ended",
        drainedFlitCount, drainedLinkCount), UVM_MEDIUM)
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB/SUMMARY", $sformatf(
      "scoreboard: %0d flit samples, %0d link samples (%0d + %0d drained at end of test)",
      flitSampleCount, linkSampleCount, drainedFlitCount, drainedLinkCount),
      UVM_MEDIUM)
  endfunction

endclass
