class fifo_monitor #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
);

  virtual fifo_if #(DATA_WIDTH, DEPTH) vif;

  mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_wr;
  mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_rd;
  fifo_scoreboard #(DATA_WIDTH) sb;  // for the flush notification

  int wr_seen, rd_seen, flush_seen;
  int occ_hist[int];

  function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif, mailbox#(bit [DATA_WIDTH-1:0]) mon2sb_wr,
               mailbox#(bit [DATA_WIDTH-1:0]) mon2sb_rd, fifo_scoreboard#(DATA_WIDTH) sb);
    this.vif       = vif;
    this.mon2sb_wr = mon2sb_wr;
    this.mon2sb_rd = mon2sb_rd;
    this.sb        = sb;
  endfunction

  task automatic run();
    bit rd_ok, wr_ok;
    int occ;

    forever begin
      @(vif.cb_mon);

      if (vif.rst_ni === 1'b1) begin  //if not in reset

        occ = vif.cb_mon.occupancy_o;
        if (!occ_hist.exists(occ)) occ_hist[occ] = 0;
        occ_hist[occ]++;

        sample_coverage(occ, vif.cb_mon.wr_en_i, vif.cb_mon.rd_en_i);

        if (vif.cb_mon.flush_i === 1'b1) begin
          sb.do_flush();
          flush_seen++;
        end else begin
          // Mirror the DUT's acceptance logic from visible pins:
          //   read_accept  = rd_en_i && !empty_o
          //   write_accept = wr_en_i && (!full_o || read_accept)
          rd_ok = vif.cb_mon.rd_en_i && !vif.cb_mon.empty_o;
          wr_ok = vif.cb_mon.wr_en_i && (!vif.cb_mon.full_o || rd_ok);

          if (wr_ok) begin
            mon2sb_wr.put(vif.cb_mon.wr_data_i);
            wr_seen++;
          end
        end

        // rd_valid_o marks the cycle rd_data_o is meaningful. Never
        // trigger on rd_en_i -- the read is registered, so rd_data_o
        // appears one cycle later.
        if (vif.cb_mon.rd_valid_o === 1'b1) begin
          mon2sb_rd.put(vif.cb_mon.rd_data_o);
          rd_seen++;
        end
      end
    end
  endtask

  function void report();
    $display("--- monitor ---");
    $display("writes accepted: %0d", wr_seen);
    $display("reads observed:  %0d", rd_seen);
    $display("flushes:         %0d", flush_seen);
    $display("--- occupancy histogram ---");
    foreach (occ_hist[i]) $display("occ[%0d] = %0d", i, occ_hist[i]);
  endfunction

  // ---------------------------------------------------------------
  // Functional coverage, collected by hand.
  //
  // Questa Altera Starter Edition lacks the svverification licence
  // feature, which gates covergroup/randomize/randcase/randsequence.
  // This builds the equivalent of:
  //
  //   cp_occ: coverpoint occupancy_o { bins empty, partial, full; }
  //   cp_op:  coverpoint {wr_en, rd_en} { bins idle, read, write, simult; }
  //   cross cp_occ, cp_op;
  //
  // using a string-keyed associative array. Bin names map directly to
  // the coverage items in the project brief.
  // ---------------------------------------------------------------
  int cov_bins[string];

  function void sample_coverage(int occ, bit wr, bit rd);
    string state, op, key;

    state = (occ == 0) ? "empty" : (occ == DEPTH) ? "full" : "partial";

    op    = (wr && rd) ? "simult" : wr ? "write" : rd ? "read" : "idle";

    key   = {state, "_", op};
    if (!cov_bins.exists(key)) cov_bins[key] = 0;
    cov_bins[key]++;
  endfunction

  function void report_coverage();
    string required[] = '{
        "empty_write",  // empty -> write
        "full_read",  // full  -> read
        "empty_read",  // empty -> read  (underflow attempt)
        "full_write",  // full  -> write (overflow attempt)
        "partial_write",
        "partial_read",
        "empty_simult",
        "partial_simult",
        "full_simult"  // simultaneous r/w at every fill level
    };
    int hit;

    $display("--- functional coverage ---");
    foreach (required[i]) begin
      if (cov_bins.exists(required[i])) begin
        hit++;
        $display("  HIT  %-16s (%0d)", required[i], cov_bins[required[i]]);
      end else begin
        $display("  MISS %-16s", required[i]);
      end
    end
    $display("coverage: %0d/%0d bins (%0.1f%%)", hit, required.size(),
             100.0 * hit / required.size());
  endfunction

endclass
