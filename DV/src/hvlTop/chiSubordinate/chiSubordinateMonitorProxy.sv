// Observes one Subordinate port through the monitor BFM. Mirror image of
// the requester monitor: a Subordinate receives REQ and never sends it, and
// has no snoop channel in either direction, so those ports do not exist
// here. [TOP:CHI_CONNECT_PORT with IS_REQUESTER=0]
//
// flitPort carries the raw sample with its node ordinal still attached.
// The typed ports lose that, and the scoreboard needs to know which port a
// flit crossed, not only what the flit said about itself.

class chiSubordinateMonitorProxy extends uvm_monitor;
  virtual chiMonitorBfm bfm;
  chiSubordinateConfig cfg;

  uvm_analysis_port#(chiRspFlitT) txRspPort;
  uvm_analysis_port#(chiDatFlitT) txDatPort;
  uvm_analysis_port#(chiReqFlitT) rxReqPort;
  uvm_analysis_port#(chiDatFlitT) rxDatPort;
  uvm_analysis_port#(chiFlitSampleT) flitPort;
  uvm_analysis_port#(chiCreditSampleT) creditPort;
  uvm_analysis_port#(chiLinkSampleT) linkPort;

  `uvm_component_utils(chiSubordinateMonitorProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    txRspPort = new("txRspPort", this);
    txDatPort = new("txDatPort", this);
    rxReqPort = new("rxReqPort", this);
    rxDatPort = new("rxDatPort", this);
    flitPort = new("flitPort", this);
    creditPort = new("creditPort", this);
    linkPort = new("linkPort", this);
  endfunction

  function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);
    if (!uvm_config_db#(chiSubordinateConfig)::get(this, "", "chiSubordinateConfig", cfg))
      `uvm_fatal("chiSubordinateConfig", "config_db get failed for key chiSubordinateConfig")
    cfg.chiNormalize();
    key = cfg.monitorKey();
    if (!uvm_config_db#(virtual chiMonitorBfm)::get(this, "", key, bfm))
      `uvm_fatal("chiSubordinateMonitorProxy", {"config_db get failed for key ", key})
  endfunction

  task run_phase(uvm_phase phase);
    bfm.waitConfigured();
    bfm.monitorStart();
    fork
      chiWatchFlits();
      chiWatchCredits();
      chiWatchLink();
    join_none
    wait(0);
  endtask

  task automatic chiWatchFlits();
    chiFlitSampleT sample;
    forever begin
      bfm.getFlitSample(sample);
      flitPort.write(sample);
      case (sample.channel)
        CHI_CH_REQ: begin
          if (sample.direction == CHI_DIR_RX)
            rxReqPort.write(unpackReq(sample.payload));
          else
            `uvm_error("chiSubordinateMonitorProxy",
              "REQ observed leaving a Subordinate port, which has no TX request channel")
        end
        CHI_CH_RSP: begin
          if (sample.direction == CHI_DIR_TX)
            txRspPort.write(unpackRsp(sample.payload));
        end
        CHI_CH_DAT: begin
          if (sample.direction == CHI_DIR_TX)
            txDatPort.write(unpackDat(sample.payload));
          else
            rxDatPort.write(unpackDat(sample.payload));
        end
        default: begin
          `uvm_error("chiSubordinateMonitorProxy",
            "SNP observed on a Subordinate port, which has no snoop channel")
        end
      endcase
    end
  endtask

  task automatic chiWatchCredits();
    chiCreditSampleT sample;
    forever begin
      bfm.getCreditSample(sample);
      creditPort.write(sample);
    end
  endtask

  task automatic chiWatchLink();
    chiLinkSampleT sample;
    forever begin
      bfm.getLinkSample(sample);
      linkPort.write(sample);
    end
  endtask
endclass
