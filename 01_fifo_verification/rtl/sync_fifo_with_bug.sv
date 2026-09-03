// Deliberately mutated copy of sync_fifo.sv, used to prove the scoreboard
// can detect real failures. NOT a design bug -- uncomment one `define below
// to select which mutation is active.


`define SIMULATION
// `define BUG_READ_OFFSET
`define BUG_PHANTOM_VALID

module sync_fifo #(
    parameter int unsigned DATA_WIDTH             = 32,
    parameter int unsigned DEPTH                  = 16,
    parameter bit          FWFT_ENABLE            = 0,
    parameter bit          OUTPUT_REGISTER_ENABLE = 1,
    parameter bit          CLEAR_MEMORY_ON_RESET  = 0,
    parameter bit          OVERFLOW_CHECK_ENABLE  = 1,
    parameter bit          UNDERFLOW_CHECK_ENABLE = 1,
    parameter bit          STICKY_ERROR_ENABLE    = 1,
    parameter int unsigned ALMOST_FULL_LEVEL      = DEPTH - 1,
    parameter int unsigned ALMOST_EMPTY_LEVEL     = 1
) (
    input  logic                       clk_i,
    input  logic                       rst_ni,
    input  logic                       flush_i,

    input  logic                       wr_en_i,
    input  logic [DATA_WIDTH-1:0]      wr_data_i,

    input  logic                       rd_en_i,
    output logic [DATA_WIDTH-1:0]      rd_data_o,
    output logic                       rd_valid_o,

    output logic                       full_o,
    output logic                       empty_o,
    output logic                       almost_full_o,
    output logic                       almost_empty_o,

    output logic [$clog2(DEPTH+1)-1:0] occupancy_o,
    output logic [$clog2(DEPTH+1)-1:0] free_count_o,

    output logic                       overflow_o,
    output logic                       underflow_o,
    output logic                       overflow_sticky_o,
    output logic                       underflow_sticky_o
);

    localparam int unsigned PTR_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    localparam int unsigned COUNT_WIDTH =
        (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);

    typedef logic [PTR_WIDTH-1:0]   ptr_t;
    typedef logic [COUNT_WIDTH-1:0] count_t;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    ptr_t   read_ptr_q;
    ptr_t   write_ptr_q;
    count_t occupancy_q;

    logic read_accept;
    logic write_accept;
    logic overflow_event;
    logic underflow_event;

    function automatic ptr_t increment_ptr(input ptr_t ptr);
        if (DEPTH <= 1) begin
            increment_ptr = '0;
        end
        else if (ptr == ptr_t'(DEPTH - 1)) begin //explicitly wraps at DEPTH-1, so depths such as 3, 5, or 10 work correctly.
            increment_ptr = '0;
        end
        else begin
            increment_ptr = ptr + ptr_t'(1);
        end
    endfunction


    `ifdef SIMULATION
    initial begin
        assert (DATA_WIDTH > 0)
            else $fatal(1, "DATA_WIDTH must be greater than zero");

        assert (DEPTH > 0)
            else $fatal(1, "DEPTH must be greater than zero");

        assert (ALMOST_FULL_LEVEL <= DEPTH)
            else $fatal(1, "ALMOST_FULL_LEVEL must be <= DEPTH");

        assert (ALMOST_EMPTY_LEVEL <= DEPTH)
            else $fatal(1, "ALMOST_EMPTY_LEVEL must be <= DEPTH");
    end
    `endif

    always_comb begin
        occupancy_o  = occupancy_q;
        free_count_o = count_t'(DEPTH) - occupancy_q;

        empty_o = (occupancy_q == count_t'(0));
        full_o  = (occupancy_q == count_t'(DEPTH));

        read_accept  = rd_en_i && !empty_o;
        write_accept = wr_en_i && (!full_o || read_accept);

        almost_full_o = (occupancy_q >= count_t'(ALMOST_FULL_LEVEL));
        almost_empty_o = (occupancy_q <= count_t'(ALMOST_EMPTY_LEVEL));

        overflow_event = (wr_en_i && full_o && (!read_accept));
        underflow_event = (rd_en_i && empty_o);
    end


    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            read_ptr_q    <= '0;
            write_ptr_q   <= '0;
            occupancy_q   <= '0;

            rd_data_o     <= '0;
            rd_valid_o    <= 1'b0;
        end
        else if (flush_i) begin
            read_ptr_q    <= '0;
            write_ptr_q   <= '0;
            occupancy_q   <= '0;

            rd_data_o     <= '0;
            rd_valid_o    <= 1'b0;
        end
        else begin
                rd_valid_o <= 1'b0;

                if (write_accept) begin
                    mem[write_ptr_q] <= wr_data_i;
                    write_ptr_q      <= increment_ptr(write_ptr_q);
                end

                // ---- Bug injection for scoreboard self-test. Enabled only
                // ---- via +define+BUG_xxx; default build is clean RTL.
                `ifdef BUG_READ_OFFSET
                    // Returns the next entry instead of the oldest.
                    // Should break FIFO ordering on every read.
                    if (read_accept) begin
                        rd_data_o   <= mem[increment_ptr(read_ptr_q)];
                        rd_valid_o  <= 1'b1;
                        read_ptr_q  <= increment_ptr(read_ptr_q);
                    end
                `elsif BUG_PHANTOM_VALID
                    // Asserts rd_valid_o even when the read was rejected,
                    // leaking stale memory. Should trip the scoreboard's
                    // "read produced data but model is empty" branch.
                    if (read_accept) begin
                        rd_data_o   <= mem[read_ptr_q];
                        rd_valid_o  <= 1'b1;
                        read_ptr_q  <= increment_ptr(read_ptr_q);
                    end
                    else if (rd_en_i) begin
                        rd_data_o   <= mem[read_ptr_q];
                        rd_valid_o  <= 1'b1;      // the bug
                    end
                `elsif BUG_NO_PTR_ADVANCE
                    // Read pointer never advances, so every read returns
                    // the same entry. Should show as duplicated data.
                    if (read_accept) begin
                        rd_data_o   <= mem[read_ptr_q];
                        rd_valid_o  <= 1'b1;
                    end
                `else
                    if (read_accept) begin
                        rd_data_o   <= mem[read_ptr_q];
                        rd_valid_o  <= 1'b1;
                        read_ptr_q  <= increment_ptr(read_ptr_q);
                    end
                `endif

                // Update occupancy from accepted transactions only.
                unique case ({write_accept, read_accept})
                    2'b10: occupancy_q <= occupancy_q + count_t'(1);
                    2'b01: occupancy_q <= occupancy_q - count_t'(1);
                    default: occupancy_q <= occupancy_q; //If {write_accept, read_accept} == 2'b11, both a write and read happen in the same clock cycle.
                                                        //The occupancy does not change in this case, so we can leave it as is.
                endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            overflow_o         <= 1'b0;
            underflow_o        <= 1'b0;
            overflow_sticky_o  <= 1'b0;
            underflow_sticky_o <= 1'b0;
        end
        else if (flush_i) begin
            overflow_o  <= 1'b0;
            underflow_o <= 1'b0;

            overflow_sticky_o  <= overflow_sticky_o;
            underflow_sticky_o <= underflow_sticky_o;
        end
        else begin
            overflow_o <= OVERFLOW_CHECK_ENABLE
                        ? overflow_event
                        : 1'b0;

            underflow_o <= UNDERFLOW_CHECK_ENABLE
                        ? underflow_event
                        : 1'b0;

            if (!STICKY_ERROR_ENABLE) begin // Sticky errors remain asserted until reset.
                overflow_sticky_o  <= 1'b0;
                underflow_sticky_o <= 1'b0;
            end
            else begin
                if (OVERFLOW_CHECK_ENABLE && overflow_event)
                    overflow_sticky_o <= 1'b1;

                if (UNDERFLOW_CHECK_ENABLE && underflow_event)
                    underflow_sticky_o <= 1'b1;
            end
        end
    end


    `ifdef SIMULATION

        // Occupancy must always remain within the configured FIFO depth.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni)
            occupancy_q <= count_t'(DEPTH)
        ) else $error("FIFO occupancy exceeded DEPTH");

        // Status flags must agree with occupancy.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni)
            empty_o == (occupancy_q == count_t'(0))
        ) else $error("empty_o does not match occupancy");

        assert property (@(posedge clk_i)
            disable iff (!rst_ni)
            full_o == (occupancy_q == count_t'(DEPTH))
        ) else $error("full_o does not match occupancy");

        // Read pointer must never address outside the memory.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni)
            read_ptr_q < DEPTH
        ) else $error("Read pointer is outside FIFO memory");

        // Write pointer must never address outside the memory.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni)
            write_ptr_q < DEPTH
        ) else $error("Write pointer is outside FIFO memory");

        // An empty FIFO must never accept a read.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni || flush_i)
            empty_o |-> !read_accept // |-> same cycle implication, so if empty_o is true, read_accept must be false in the same cycle.
        ) else $error("Read was accepted while FIFO was empty");

        // A full FIFO may accept a write only when a read is also accepted.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni || flush_i)
            (full_o && write_accept) |-> read_accept // |-> same cycle implication, so if full_o is true and write_accept is true, read_accept must be true in the same cycle.
        ) else $error("Write was accepted into full FIFO without a read");

        // Simultaneous accepted read/write must keep occupancy unchanged.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni || flush_i)
            (read_accept && write_accept)
            |=> occupancy_q == $past(occupancy_q) // |=> next clock cycle implication, so if read_accept and write_accept are both true, occupancy_q must be equal to its previous value in the same cycle.
        ) else $error("Occupancy changed during simultaneous read/write");

        // An accepted write without a read must increase occupancy by one.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni || flush_i)
            (write_accept && !read_accept)
            |=> occupancy_q == ($past(occupancy_q) + count_t'(1)) // |=> next clock cycle implication, so if write_accept is true and read_accept is false, occupancy_q must be equal to its previous value plus one in the same cycle.
        ) else $error("Occupancy did not increment after accepted write");

        // An accepted read without a write must decrease occupancy by one.
        assert property (@(posedge clk_i)
            disable iff (!rst_ni || flush_i)
            (read_accept && !write_accept)
            |=> occupancy_q == ($past(occupancy_q) - count_t'(1)) // |=> next clock cycle implication, so if read_accept is true and write_accept is false, occupancy_q must be equal to its previous value minus one in the same cycle.
        ) else $error("Occupancy did not decrement after accepted read");

    `endif
endmodule