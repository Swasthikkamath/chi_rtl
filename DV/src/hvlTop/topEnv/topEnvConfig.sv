//==============================================================================
// topEnvConfig
//
// One configuration object for the whole top-level environment. The base
// test builds it, optionally flips knobs, and publishes it before the env is
// created; the env and the scoreboard's four reference models all read it.
//
// The error-expectation knobs exist because the directed error tests make the
// bench itself misbehave on purpose [ASSUMPTION:17]: injecting a parity or
// credit fault means the monitors will observe the bench violating the very
// rules the link model checks. The knobs tell the scoreboard which violations
// the test intends, so that an intended injection is required rather than
// forgiven, and an unintended one is still a failure.
//==============================================================================

class topEnvConfig extends uvm_object;

  // When 0 every agent is built passive: monitors and coverage exist so the
  // scoreboard still sees the boundary, but no driver or sequencer is built.
  // Defaults to active because every useful test drives stimulus.
  bit activeStimulus;

  // Per-agent outstanding-transaction caps. Zero leaves the agent's own
  // default in place (the config objects normalise zero to the cap).
  int unsigned requesterOutstanding;
  int unsigned subordinateOutstanding;

  // Subordinate policy defaults, copied into every subordinate agent config.
  // A test that wants retries or error injection on one subordinate edits
  // that agent's config after the env builds it.
  bit        subordinateEnableRetry;
  chiRespErrE subordinateInjectRespErr;

  // Directed-error expectations. A directed test sets the matching bit; the
  // link model then requires the DUT's error output to fire (absence is a
  // failure) and, for the credit test, forgives the bench-side credit
  // violation that provokes it.
  bit expectLinkParityError;
  bit expectLinkCreditError;
  bit allowTbCreditViolation;

  // Per-model check enables. All default on; a test disables a model only to
  // isolate a known failure while debugging, never in a regression.
  bit enableLinkChecks;
  bit enableLifecycleChecks;
  bit enableDirectoryChecks;
  bit enableMemoryChecks;

  `uvm_object_utils(topEnvConfig)

  function new(string name = "topEnvConfig");
    super.new(name);
    activeStimulus = 1'b1;
    requesterOutstanding = 0;
    subordinateOutstanding = 0;
    subordinateEnableRetry = 1'b0;
    subordinateInjectRespErr = RESP_ERR_OK;
    expectLinkParityError = 1'b0;
    expectLinkCreditError = 1'b0;
    allowTbCreditViolation = 1'b0;
    enableLinkChecks = 1'b1;
    enableLifecycleChecks = 1'b1;
    enableDirectoryChecks = 1'b1;
    enableMemoryChecks = 1'b1;
  endfunction

endclass
