# Production-Grade Single-Clock Synchronous FIFO Requirements

## 1. Objective

Design a synthesizable, parameterized, single-clock synchronous FIFO in SystemVerilog. The FIFO shall reliably store and retrieve data in first-in-first-out order and correctly handle reset, flush, simultaneous operations, boundary conditions, overflow, underflow, programmable thresholds, and non-power-of-two depths.

The design must be suitable for FPGA and ASIC synthesis, linting, simulation, formal verification, and integration into production RTL.

## 2. Parameters

```systemverilog
parameter int unsigned DATA_WIDTH             = 32;
parameter int unsigned DEPTH                  = 16;
parameter bit          FWFT_ENABLE            = 0;
parameter bit          OUTPUT_REGISTER_ENABLE = 1;
parameter bit          CLEAR_MEMORY_ON_RESET  = 0;
parameter bit          OVERFLOW_CHECK_ENABLE  = 1;
parameter bit          UNDERFLOW_CHECK_ENABLE = 1;
parameter bit          STICKY_ERROR_ENABLE    = 1;
parameter int unsigned ALMOST_FULL_LEVEL      = DEPTH - 1;
parameter int unsigned ALMOST_EMPTY_LEVEL     = 1;
```

Parameter requirements:

* `DATA_WIDTH` shall be greater than zero.
* `DEPTH` shall be greater than zero.
* Arbitrary depths, including non-power-of-two depths, shall be supported.
* `ALMOST_FULL_LEVEL` shall be between `0` and `DEPTH`.
* `ALMOST_EMPTY_LEVEL` shall be between `0` and `DEPTH`.
* Illegal parameter values shall produce elaboration-time errors.
* Counter and pointer widths shall be derived using `$clog2`.
* Special handling shall be provided for `DEPTH == 1` to avoid zero-width signals.

## 3. Interface

```systemverilog
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
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         flush_i,

    input  logic                         wr_en_i,
    input  logic [DATA_WIDTH-1:0]        wr_data_i,

    input  logic                         rd_en_i,
    output logic [DATA_WIDTH-1:0]        rd_data_o,
    output logic                         rd_valid_o,

    output logic                         full_o,
    output logic                         empty_o,
    output logic                         almost_full_o,
    output logic                         almost_empty_o,

    output logic [$clog2(DEPTH+1)-1:0]   occupancy_o,
    output logic [$clog2(DEPTH+1)-1:0]   free_count_o,

    output logic                         overflow_o,
    output logic                         underflow_o,
    output logic                         overflow_sticky_o,
    output logic                         underflow_sticky_o
);
```

## 4. Clock and Reset

* All FIFO state shall update only on the rising edge of `clk_i`.
* `rst_ni` shall be an active-low reset.
* Reset assertion may be asynchronous.
* Reset deassertion shall be treated as synchronous to `clk_i`.
* After reset:

  * FIFO occupancy shall be zero.
  * Read and write pointers shall be zero.
  * `empty_o` shall be asserted.
  * `full_o` shall be deasserted.
  * Error flags shall be cleared.
  * `rd_valid_o` shall be deasserted.
  * `rd_data_o` shall be set to a defined value, preferably `'0`.
* The memory array need not be physically cleared unless `CLEAR_MEMORY_ON_RESET == 1`.
* No stale memory value shall be marked valid after reset.

## 5. Flush Operation

* `flush_i` shall synchronously discard all FIFO contents.
* Flush shall have priority over read and write requests.
* When `flush_i` is sampled high:

  * Read and write requests shall not be accepted.
  * Occupancy shall become zero.
  * Read and write pointers shall return to zero.
  * `empty_o` shall assert.
  * `full_o` shall deassert.
  * `rd_valid_o` shall deassert.
* Flush shall not be reported as underflow or overflow.
* Sticky error flags should remain unchanged during flush unless explicitly cleared by reset.
* Memory clearing during flush shall follow `CLEAR_MEMORY_ON_RESET`.

## 6. Accepted Operations

The implementation shall derive internal acceptance signals:

```systemverilog
write_accept = wr_en_i && (!full_o || read_accept);
read_accept  = rd_en_i && !empty_o;
```

For standard registered-read mode, reading an empty FIFO is never accepted.

A write while full may be accepted only when a valid read is accepted during the same cycle, because the read frees one entry.

## 7. Read and Write Behavior

### Write

* When `write_accept` is true:

  * `wr_data_i` shall be written at the current write pointer.
  * The write pointer shall advance by one position.
* When the write pointer reaches `DEPTH-1`, it shall wrap to zero.
* A rejected write shall not modify memory, pointers, occupancy, or FIFO ordering.

### Read

* When `read_accept` is true:

  * The oldest stored element shall be returned.
  * The read pointer shall advance by one position.
  * `rd_valid_o` shall indicate that `rd_data_o` contains a valid read result.
* When the read pointer reaches `DEPTH-1`, it shall wrap to zero.
* A rejected read shall not advance the read pointer or change occupancy.

## 8. Simultaneous Read and Write Cases

| Initial state    | `wr_en_i` | `rd_en_i` | Required behavior                                |
| ---------------- | --------: | --------: | ------------------------------------------------ |
| Empty            |         0 |         0 | No operation                                     |
| Empty            |         0 |         1 | Underflow; no read accepted                      |
| Empty            |         1 |         0 | Accept write; occupancy becomes 1                |
| Empty            |         1 |         1 | Accept write; read behavior depends on FWFT mode |
| Partially filled |         1 |         1 | Accept both; occupancy unchanged                 |
| Full             |         1 |         0 | Overflow; write rejected                         |
| Full             |         0 |         1 | Accept read; occupancy becomes `DEPTH-1`         |
| Full             |         1 |         1 | Accept both; occupancy remains `DEPTH`           |

For simultaneous accepted read and write:

* FIFO ordering shall be preserved.
* The read shall return the oldest pre-existing entry.
* The newly written entry shall become the newest FIFO entry.
* When the read and write pointers address the same physical memory location in a full FIFO, behavior must not depend on an inferred RAM’s undefined read-during-write mode.
* Explicit bypassing, ordering logic, or a documented RAM inference strategy shall guarantee deterministic behavior.

## 9. Occupancy Management

Occupancy shall represent the number of valid entries currently stored.

```systemverilog
case ({write_accept, read_accept})
    2'b10: occupancy_next = occupancy + 1;
    2'b01: occupancy_next = occupancy - 1;
    default: occupancy_next = occupancy;
endcase
```

Required range:

```text
0 <= occupancy <= DEPTH
```

Occupancy shall never wrap, underflow, overflow, or enter an illegal state.

```systemverilog
empty_o      = (occupancy_o == 0);
full_o       = (occupancy_o == DEPTH);
free_count_o = DEPTH - occupancy_o;
```

## 10. Status Flags

### Empty

* Assert when occupancy equals zero.
* Deassert immediately after a write is accepted into an empty FIFO.
* Remain asserted following a rejected read from an empty FIFO.

### Full

* Assert when occupancy equals `DEPTH`.
* Deassert when a read without a replacing write is accepted.

### Almost Empty

```systemverilog
almost_empty_o = (occupancy_o <= ALMOST_EMPTY_LEVEL);
```

### Almost Full

```systemverilog
almost_full_o = (occupancy_o >= ALMOST_FULL_LEVEL);
```

All flags shall correspond to the current registered FIFO state and shall not glitch between clock edges.

## 11. Read Modes

### Standard Registered-Read Mode

When `FWFT_ENABLE == 0`:

* `rd_data_o` shall update following an accepted read.
* `rd_valid_o` shall pulse for each accepted read.
* Read latency shall be exactly one clock cycle unless otherwise explicitly documented.
* A read from empty shall not produce valid data.

### First-Word Fall-Through Mode

When `FWFT_ENABLE == 1`:

* Whenever the FIFO is non-empty, `rd_data_o` shall present the oldest available entry.
* `rd_valid_o` shall indicate that the output currently contains valid data.
* The first element written into an empty FIFO shall become visible without requiring a separate read request.
* `rd_en_i` shall consume the currently presented word.
* Back-to-back reads shall sustain one word per cycle.
* Empty-to-write and simultaneous empty read/write behavior shall be explicitly bypassed so the new input word is presented correctly.
* No stale word shall be reported as valid.

The selected mode shall have unambiguous and documented latency.

## 12. Output Register

When `OUTPUT_REGISTER_ENABLE == 1`:

* Output data shall be held in a register.
* The output shall remain stable when no new valid word is produced.
* The register shall improve timing isolation from the memory array.
* `rd_valid_o` shall align exactly with the registered output.

When disabled, combinational memory output is permitted only if supported by the target implementation and does not introduce undefined behavior.

## 13. Overflow Handling

Overflow is a write request that cannot be accepted:

```systemverilog
overflow_event = wr_en_i && full_o && !read_accept;
```

Requirements:

* Overflow shall not overwrite unread data.
* Write pointer and occupancy shall remain unchanged.
* `overflow_o` shall pulse for exactly one cycle per overflow event.
* If overflow checking is disabled, the request shall still be safely rejected; only error reporting may be disabled.
* If `STICKY_ERROR_ENABLE == 1`, `overflow_sticky_o` shall remain asserted until reset.
* A simultaneous accepted read and write while full shall not generate overflow.

## 14. Underflow Handling

Underflow is a read request when no data is available:

```systemverilog
underflow_event = rd_en_i && empty_o;
```

Requirements:

* Underflow shall not advance the read pointer.
* Occupancy shall remain zero.
* `rd_valid_o` shall not indicate a successful read.
* `underflow_o` shall pulse for exactly one cycle per underflow event.
* If underflow checking is disabled, the request shall still be safely rejected; only error reporting may be disabled.
* If `STICKY_ERROR_ENABLE == 1`, `underflow_sticky_o` shall remain asserted until reset.
* `rd_data_o` may retain its previous value or become zero, but it shall never be marked valid.

## 15. Pointer Handling

* Separate read and write pointers shall be maintained.
* Pointer range shall be exactly `0` through `DEPTH-1`.
* Non-power-of-two depths shall use explicit terminal-count wrapping.
* Pointer arithmetic shall not access memory outside the declared array.
* Full and empty determination shall use occupancy or equivalent phase-aware logic.
* Pointer equality alone shall not be used to distinguish full from empty.

## 16. Memory Implementation

The storage array shall contain exactly `DEPTH` entries of `DATA_WIDTH` bits.

```systemverilog
logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
```

Requirements:

* The implementation should allow inference of registers, distributed RAM, block RAM, or ASIC SRAM.
* No out-of-range array access is permitted.
* Synthesis behavior shall not depend on simulator-only initialization.
* Simultaneous read/write behavior shall be deterministic.
* Reset logic shall not unintentionally prevent block-RAM inference.
* Memory clearing shall be optional because resetting every memory element may force register implementation.

## 17. Data Integrity Requirements

* Every accepted write shall produce exactly one readable FIFO entry.
* Every accepted read shall consume exactly one FIFO entry.
* Data shall emerge in the same order in which writes were accepted.
* Rejected writes shall never alter stored data.
* Rejected reads shall never remove data.
* No entry shall be duplicated, skipped, corrupted, or reordered.
* Pointer wraparound shall not change ordering.
* Continuous simultaneous reads and writes shall support one transfer in each direction per clock cycle.
* Data integrity shall hold across repeated full-to-not-full and empty-to-not-empty transitions.

## 18. Special Cases

### `DEPTH == 1`

The FIFO shall correctly operate as a one-entry buffer:

* Write to empty shall fill it.
* Read from full shall empty it.
* Simultaneous read/write while full shall replace the consumed entry without generating overflow.
* Pointer widths shall remain legal.
* No zero-width vectors are permitted.

### Non-Power-of-Two Depth

For values such as 3, 5, 10, or 17:

* Pointers shall wrap at `DEPTH-1`.
* Unused binary pointer states shall never index memory.
* Occupancy shall still range from zero through `DEPTH`.

### Continuous Traffic

The FIFO shall support:

* Continuous writes until full.
* Continuous reads until empty.
* Continuous simultaneous reads and writes.
* Alternating read/write activity.
* Bursts of arbitrary length.
* Pointer wraparound multiple times.
* Backpressure at both full and empty boundaries.

## 19. Priority Rules

Priority shall be:

1. Active reset
2. Flush
3. Accepted read/write operations
4. Error reporting for rejected requests
5. Idle state

Reset and flush shall prevent memory transactions from being accepted in the same cycle.

## 20. Coding Requirements

* Use synthesizable SystemVerilog.
* Use `logic`, `always_ff`, and `always_comb`.
* Use nonblocking assignments for sequential state.
* Do not use delays, event controls inside procedural logic, force/release, or simulation-only constructs in functional RTL.
* Avoid inferred latches.
* Avoid combinational loops.
* Avoid multiple drivers.
* Avoid unsized constants in width-sensitive expressions.
* Use explicit type and width conversions where needed.
* All outputs shall be assigned deterministically.
* Internal next-state logic shall have safe defaults.
* Parameter validation may use elaboration-time assertions.
* The design shall compile without warnings.

## 21. Assertions

The design shall include bindable or synthesis-guarded SystemVerilog Assertions covering at least:

```systemverilog
assert property (@(posedge clk_i) occupancy_o <= DEPTH);
assert property (@(posedge clk_i) full_o == (occupancy_o == DEPTH));
assert property (@(posedge clk_i) empty_o == (occupancy_o == 0));
assert property (@(posedge clk_i) !(full_o && empty_o))
    if (DEPTH > 0);
```

Additional properties shall verify:

* Occupancy increments only for write-only acceptance.
* Occupancy decrements only for read-only acceptance.
* Occupancy remains stable for simultaneous accepted read/write.
* Occupancy remains stable during rejected operations.
* Read pointer advances only on accepted reads.
* Write pointer advances only on accepted writes.
* No write is accepted while full unless a read is accepted.
* No read is accepted while empty.
* Overflow does not modify FIFO contents.
* Underflow does not modify FIFO contents.
* Flush produces an empty FIFO.
* Accepted data is returned in FIFO order.
* Flags match occupancy.
* No unknown values appear on control outputs after reset.
* Pointer values always remain below `DEPTH`.

## 22. Verification Requirements

A self-checking testbench shall use a queue-based reference model and include:

* Reset from every FIFO state.
* Flush from empty, partially filled, and full states.
* Write/read of randomized data.
* Fill-to-full and drain-to-empty tests.
* Overflow attempts.
* Underflow attempts.
* Simultaneous reads and writes.
* Simultaneous read/write at full.
* Simultaneous read/write at empty.
* Pointer wraparound.
* Multiple complete wraparound cycles.
* Threshold boundary transitions.
* `DEPTH == 1`.
* Power-of-two and non-power-of-two depths.
* Minimum and large data widths.
* Long randomized traffic with a scoreboard.
* Back-to-back reset and flush.
* Requests asserted during reset and flush.
* FWFT and standard-read configurations.
* Output-register enabled and disabled configurations.
* Sticky and pulse error behavior.

Functional coverage shall include:

* Empty → non-empty.
* Non-empty → empty.
* Not-full → full.
* Full → not-full.
* Every occupancy value.
* Read/write acceptance combinations.
* Overflow and underflow.
* Pointer wraparound.
* Simultaneous operation at each boundary.
* Almost-full and almost-empty assertion/deassertion.

## 23. Acceptance Criteria

The FIFO is complete only when:

* RTL compiles without errors or unresolved warnings.
* Lint reports no critical violations.
* All directed and randomized tests pass.
* Assertions pass.
* Functional coverage reaches the agreed target, preferably 100% for defined corner cases.
* Synthesis succeeds for FPGA and/or ASIC targets.
* No unintended latch, combinational loop, or out-of-range memory access exists.
* FIFO ordering is proven through simulation or formal verification.
* All supported parameter combinations elaborate correctly.
* Behavior is deterministic at empty, full, simultaneous-access, and pointer-wrap boundaries.
