// Write agent. Drives only wr_en_i/wr_data_i, and runs concurrently with
// the read agent. Both share one interface, so both must arbitrate for it
// -- without the semaphore they would write cb_drv in the same instant
// and the last write would silently win.
class fifo_wr_driver #(parameter int unsigned DATA_WIDTH = 8,
                       parameter int unsigned DEPTH      = 4);

    virtual fifo_if #(DATA_WIDTH, DEPTH) vif;
    semaphore                            bus_sem;
    int                                  n_writes;
    int                                  drive_count;
    event                                done;

    function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
                 semaphore                            bus_sem,
                 int                                  n_writes);
        this.vif      = vif;
        this.bus_sem  = bus_sem;
        this.n_writes = n_writes;
    endfunction

    task automatic run();
        repeat (n_writes) begin
            bus_sem.get(1);                 // claim the bus (blocks if held)
            vif.cb_drv.wr_en_i   <= 1'b1;
            vif.cb_drv.wr_data_i <= $urandom_range(8'h01, 8'hFE);
            @(vif.cb_drv);
            vif.cb_drv.wr_en_i   <= 1'b0;
            bus_sem.put(1);                 // release it
            drive_count++;
        end
        -> done;
    endtask

endclass