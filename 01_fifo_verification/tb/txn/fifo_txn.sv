class fifo_txn #(parameter int unsigned DATA_WIDTH = 8);

    rand bit                  wr_en;
    rand bit                  rd_en;
    rand bit [DATA_WIDTH-1:0] wr_data;

    // Keep 0x00 and 0xFF out of the stream so they stay unambiguous
    // as sentinels when they appear in a waveform or log.
    constraint c_data { wr_data inside {[8'h01:8'hFE]}; }

    // Default traffic mix, overridable per test.
    constraint c_mix {
        wr_en dist {1 := 70, 0 := 30};
        rd_en dist {1 := 40, 0 := 60};
    }

    function new();
    endfunction

    function string convert2string();
        return $sformatf("wr_en=%0b rd_en=%0b wr_data=0x%02h",
                         wr_en, rd_en, wr_data);
    endfunction
    // Starter Edition lacks the svverification license, so randomize() is
    // unavailable. The constraint blocks above document intent and go live
    // on a full-license simulator.
    function void randomize_manual();
        wr_data = $urandom_range(8'h01, 8'hFE);      // mirrors c_data
        wr_en   = ($urandom_range(1, 100) <= 70);    // mirrors c_mix
        rd_en   = ($urandom_range(1, 100) <= 40);
    endfunction
endclass