// Several line-sized intents, posted before any of them is waited
// for, so the driver can have more than one outstanding.

class chiBurstIntentSeq extends chiRequesterSeq;
  chiRequesterIntentE intent;
  int unsigned count;
  int unsigned lineBase;

  `uvm_object_utils(chiBurstIntentSeq)

  function new(string name = "chiBurstIntentSeq");
    super.new(name);
    intent = CHI_INTENT_READ_NO_SNP;
    count = 4;
    lineBase = 0;
  endfunction

  task body();
    chiBurstIntent(intent, count, lineBase);
  endtask
endclass
