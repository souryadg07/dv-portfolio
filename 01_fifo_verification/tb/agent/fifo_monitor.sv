class fifo_monitor #(parameter int unsigned DATA_WIDTH = 8,
                     parameter int unsigned DEPTH      = 4);

    virtual fifo_if #(DATA_WIDTH, DEPTH) vif;

    mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_wr;
    mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_rd;
    fifo_scoreboard #(DATA_WIDTH)   sb;      // for the flush notification

    int wr_seen, rd_seen, flush_seen;
    int occ_hist[int];

    function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
                 mailbox #(bit [DATA_WIDTH-1:0])      mon2sb_wr,
                 mailbox #(bit [DATA_WIDTH-1:0])      mon2sb_rd,
                 fifo_scoreboard #(DATA_WIDTH)        sb);
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

            if (vif.rst_ni === 1'b1) begin //if not in reset

                occ = vif.cb_mon.occupancy_o;
                if (!occ_hist.exists(occ)) occ_hist[occ] = 0;
                occ_hist[occ]++;

                if (vif.cb_mon.flush_i === 1'b1) begin
                    sb.do_flush();
                    flush_seen++;
                end
                else begin
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

endclass