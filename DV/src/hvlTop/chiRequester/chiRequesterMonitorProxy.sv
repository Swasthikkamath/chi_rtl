// Observes one requester port through the monitor BFM. The analysis
// ports are what the scoreboard will subscribe to. This class never
// drives a pin.

class chiRequesterMonitorProxy extends uvm_monitor;
  virtual chiMonitorBfm bfm;
  chiRequesterConfig cfg;

  uvm_analysis_port#(chiReqFlitT) txReqPort;
  uvm_analysis_port#(chiRspFlitT) txRspPort;
  uvm_analysis_port#(chiDatFlitT) txDatPort;
  uvm_analysis_port#(chiReqFlitT) rxReqPort;
  uvm_analysis_port#(chiRspFlitT) rxRspPort;
  uvm_analysis_port#(chiDatFlitT) rxDatPort;
  uvm_analysis_port#(chiSnpFlitT) rxSnpPort;
  uvm_analysis_port#(chiCreditSampleT) creditPort;
  uvm_analysis_port#(chiLinkSampleT) linkPort;

  `uvm_component_utils(chiRequesterMonitorProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    txReqPort = new("txReqPort", this);
    txRspPort = new("txRspPort", this);
    txDatPort = new("txDatPort", this);
    rxReqPort = new("rxReqPort", this);
    rxRspPort = new("rxRspPort", this);
    rxDatPort = new("rxDatPort", this);
    rxSnpPort = new("rxSnpPort", this);
    creditPort = new("creditPort", this);
    linkPort = new("linkPort", this);
  endfunction

  function void build_phase(uvm_phase phase);
    string key;
    super.build_phase(phase);
    if (!uvm_config_db#(chiRequesterConfig)::get(this, "", "chiRequesterConfig", cfg))
      `uvm_fatal("chiRequesterConfig", "config_db get failed for key chiRequesterConfig")
    cfg.chiNormalize();
    key = cfg.monitorKey();
    if (!uvm_config_db#(virtual chiMonitorBfm)::get(this, "", key, bfm))
      `uvm_fatal("chiRequesterMonitorProxy", {"config_db get failed for key ", key})
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
      case (sample.channel)
        CHI_CH_REQ: begin
          if (sample.direction == CHI_DIR_TX)
            txReqPort.write(unpackReq(sample.payload));
          else
            rxReqPort.write(unpackReq(sample.payload));
        end
        CHI_CH_RSP: begin
          if (sample.direction == CHI_DIR_TX)
            txRspPort.write(unpackRsp(sample.payload));
          else
            rxRspPort.write(unpackRsp(sample.payload));
        end
        CHI_CH_DAT: begin
          if (sample.direction == CHI_DIR_TX)
            txDatPort.write(unpackDat(sample.payload));
          else
            rxDatPort.write(unpackDat(sample.payload));
        end
        default: rxSnpPort.write(unpackSnp(sample.payload));
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
