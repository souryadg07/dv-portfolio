`timescale 1ns/1ps
`define DUMP
module tb_sync_fifo;

    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned DEPTH      = 4;

    logic clk_i;
    logic rst_ni;
    logic flush_i;

    logic                  wr_en_i;
    logic [DATA_WIDTH-1:0] wr_data_i;

    logic                  rd_en_i;
    logic [DATA_WIDTH-1:0] rd_data_o;
    logic                  rd_valid_o;

    logic full_o;
    logic empty_o;
    logic almost_full_o;
    logic almost_empty_o;

    logic [$clog2(DEPTH+1)-1:0] occupancy_o;
    logic [$clog2(DEPTH+1)-1:0] free_count_o;

    logic overflow_o;
    logic underflow_o;
    logic overflow_sticky_o;
    logic underflow_sticky_o;

    // 100 MHz clock
    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // One waveform idiom for both simulators: run.py passes +define+DUMP and
    // +wave=<path>, so Questa and Verilator emit the same VCD for GTKWave.
    `ifdef DUMP
    initial begin
        string wave_file;
        if (!$value$plusargs("wave=%s", wave_file))
            wave_file = "dump.vcd";
        $dumpfile(wave_file);
        $dumpvars(0, tb_sync_fifo);
    end
    `endif

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .FWFT_ENABLE(0),
        .OUTPUT_REGISTER_ENABLE(1),
        .CLEAR_MEMORY_ON_RESET(0)
    ) dut (
        .*
    );


    task automatic fifo_write(
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            // Drive inputs away from the active clock edge.
            @(negedge clk_i);
            wr_data_i = data;
            wr_en_i   = 1'b1;

            // DUT accepts the write here.
            @(posedge clk_i);
            #1;

            assert (!overflow_o)
                $display("PASS: Wrote 0x%0h, occupancy=%0d",
                         data, occupancy_o);
            else
                $fatal(1, "FAIL: Overflow while writing 0x%0h", data);

            @(negedge clk_i);
            wr_en_i   = 1'b0;
            wr_data_i = '0;
        end
    endtask


    // Read one data item and check it against the expected value.
    task automatic fifo_read(
        input logic [DATA_WIDTH-1:0] expected_data
    );
        begin
            @(negedge clk_i);
            rd_en_i = 1'b1;

            @(posedge clk_i);
            #1;

            assert (rd_valid_o)
                $display("PASS: Read valid asserted");
            else
                $fatal(1, "FAIL: rd_valid_o was not asserted");

            assert (rd_data_o === expected_data)
                $display("PASS: Read 0x%0h, expected 0x%0h, occupancy=%0d",
                         rd_data_o, expected_data, occupancy_o);
            else
                $fatal(1,
                       "FAIL: Read 0x%0h, expected 0x%0h",
                       rd_data_o, expected_data);

            assert (!underflow_o)
                $display("PASS: No underflow during valid read");
            else
                $fatal(1, "FAIL: Underflow occurred during valid read");

            @(negedge clk_i);
            rd_en_i = 1'b0;
        end
    endtask


    // Flush the FIFO and check that it returns to the empty state.
    task automatic fifo_flush;
        begin
            @(negedge clk_i);
            flush_i = 1'b1;

            @(posedge clk_i);
            #1;

            assert (empty_o)
                $display("PASS: FIFO is empty after flush");
            else
                $fatal(1, "FAIL: FIFO is not empty after flush");

            assert (!full_o)
                $display("PASS: FIFO is not full after flush");
            else
                $fatal(1, "FAIL: FIFO remains full after flush");

            assert (occupancy_o == 0)
                $display("PASS: Occupancy is zero after flush");
            else
                $fatal(1,
                       "FAIL: Occupancy after flush is %0d",
                       occupancy_o);

            assert (free_count_o == DEPTH)
                $display("PASS: Free count equals DEPTH after flush");
            else
                $fatal(1,
                       "FAIL: Free count is %0d, expected %0d",
                       free_count_o, DEPTH);

            assert (!rd_valid_o)
                $display("PASS: Read-valid is cleared after flush");
            else
                $fatal(1, "FAIL: rd_valid_o remains asserted after flush");

            @(negedge clk_i);
            flush_i = 1'b0;
        end
    endtask


    initial begin
        rst_ni  = 1'b0;
        flush_i = 1'b0;
        wr_en_i = 1'b0;
        wr_data_i = '0;
        rd_en_i = 1'b0;

        // Hold reset for two clock cycles.
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        // Avoid checking in the same simulation region as the clock edge.
        @(posedge clk_i);
        #1;

        assert (empty_o)
            $display("PASS: FIFO is empty after reset");
        else
            $fatal(1, "FAIL: FIFO must be empty after reset");

        assert (!full_o)
            $display("PASS: FIFO is not full after reset");
        else
            $fatal(1, "FAIL: FIFO must not be full after reset");

        assert (occupancy_o == 0)
            $display("PASS: FIFO occupancy is zero after reset");
        else
            $fatal(1, "FAIL: FIFO occupancy must be zero after reset");

        // ------------------------------------------------------------
        // Write test
        // ------------------------------------------------------------
        fifo_write(8'h11);
        fifo_write(8'h22);
        fifo_write(8'h33);

        assert (occupancy_o == 3)
            $display("PASS: Occupancy is 3 after three writes");
        else
            $fatal(1,
                   "FAIL: Occupancy is %0d, expected 3",
                   occupancy_o);

        // ------------------------------------------------------------
        // Read test
        // ------------------------------------------------------------
        fifo_read(8'h11);
        fifo_read(8'h22);

        assert (occupancy_o == 1)
            $display("PASS: Occupancy is 1 after two reads");
        else
            $fatal(1,
                   "FAIL: Occupancy is %0d, expected 1",
                   occupancy_o);

        // ------------------------------------------------------------
        // Flush test
        // ------------------------------------------------------------
        fifo_write(8'h44);
        fifo_write(8'h55);

        fifo_flush();

        // Verify that the FIFO can be reused after flushing.
        fifo_write(8'hA5);
        fifo_read(8'hA5);

        assert (empty_o)
            $display("PASS: FIFO is reusable after flush");
        else
            $fatal(1, "FAIL: FIFO is not empty after final read");

        $display("========================================");
        $display("ALL FIFO TESTS PASSED");
        $display("========================================");

        $finish;
    end

endmodule