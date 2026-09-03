class fifo_scoreboard #(parameter int unsigned DATA_WIDTH = 8);

    mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_wr;
    mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_rd;

    bit [DATA_WIDTH-1:0] model_q[$];      // the reference model

    int match_count;
    int mismatch_count;
    int flush_count;
    int flushed_items;

    function new(mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_wr,
                 mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_rd);
        this.mon2sb_wr = mon2sb_wr;
        this.mon2sb_rd = mon2sb_rd;
    endfunction

    // Called by the monitor when a write is accepted.
    task automatic run_writes();
        bit [DATA_WIDTH-1:0] d;
        forever begin
            mon2sb_wr.get(d);
            model_q.push_back(d);
        end
    endtask

    // Called by the monitor when rd_valid_o is high.
    task automatic run_reads();
        bit [DATA_WIDTH-1:0] observed;
        bit [DATA_WIDTH-1:0] expected;
        forever begin
            mon2sb_rd.get(observed);

            if (model_q.size() == 0) begin
                $error("SCOREBOARD: read produced 0x%02h but model is empty",
                       observed);
                mismatch_count++;
            end
            else begin
                expected = model_q.pop_front();
                if (observed === expected) begin
                    match_count++;
                end
                else begin
                    $error("SCOREBOARD: expected 0x%02h, got 0x%02h",
                           expected, observed);
                    mismatch_count++;
                end
            end
        end
    endtask

    // The DUT discards its contents on flush, so the model must too.
    function void do_flush();
        flushed_items += model_q.size();
        model_q.delete();
        flush_count++;
    endfunction

    function void report();
        $display("--- scoreboard ---");
        $display("matched:        %0d", match_count);
        $display("mismatched:     %0d", mismatch_count);
        $display("flushes:        %0d", flush_count);
        $display("flushed items:  %0d", flushed_items);
        $display("left in model:  %0d", model_q.size());
    endfunction

endclass