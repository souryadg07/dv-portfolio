# 01 — Synchronous FIFO Verification

A layered, class-based SystemVerilog verification environment for a parameterised
synchronous FIFO, built without UVM. Stimulus, observation, and checking are
separated into independent components communicating through mailboxes.

```
mingw32-make TB=tb/top/tb_v4.sv TB_TOP=tb_sync_fifo_v4 SRC=tb/interface/fifo_if.sv
```

---

## 1. DUT

`rtl/sync_fifo.sv` — a synchronous FIFO with registered read data.

| Parameter | Default | Notes |
|---|---|---|
| `DATA_WIDTH` | 32 | verified at 8 |
| `DEPTH` | 16 | verified at 4 |
| `FWFT_ENABLE` | 0 | **declared but not implemented** |
| `OUTPUT_REGISTER_ENABLE` | 1 | **declared but not implemented** |
| `CLEAR_MEMORY_ON_RESET` | 0 | **declared but not implemented** |
| `OVERFLOW_CHECK_ENABLE` | 1 | gates `overflow_o` |
| `UNDERFLOW_CHECK_ENABLE` | 1 | gates `underflow_o` |
| `STICKY_ERROR_ENABLE` | 1 | gates the sticky flags |
| `ALMOST_FULL_LEVEL` | `DEPTH-1` | |
| `ALMOST_EMPTY_LEVEL` | 1 | |

Key behaviours the environment relies on:

```systemverilog
read_accept  = rd_en_i && !empty_o;
write_accept = wr_en_i && (!full_o || read_accept);
```

A write into a full FIFO is **rejected**, not queued, unless a read is accepted the
same cycle. `rd_data_o` and `rd_valid_o` are registered, so read data appears one
cycle after the read is accepted. `overflow_o` and `underflow_o` are one-cycle
pulses; the `_sticky_` variants latch until reset.

---

## 2. Verification architecture

```
generator (inline)  →  mailbox  →  driver  →  DUT pins
                                                 │
                                              monitor
                                                 │
                                      ┌──────────┴──────────┐
                                   wr mailbox          rd mailbox
                                      └──────────┬──────────┘
                                            scoreboard
                                          (queue model)
```

| Component | File | Responsibility |
|---|---|---|
| Interface | `tb/interface/fifo_if.sv` | signal bundle, two clocking blocks, three modports |
| Transaction | `tb/txn/fifo_txn.sv` | `wr_en`, `rd_en`, `wr_data` + constraints |
| Driver | `tb/agent/fifo_driver.sv` | pulls transactions, drives pins, checks nothing |
| Write / read agents | `tb/agent/fifo_{wr,rd}_driver.sv` | independent producer and consumer |
| Monitor | `tb/agent/fifo_monitor.sv` | passive; reports accepted writes and valid reads |
| Scoreboard | `tb/agent/fifo_scoreboard.sv` | queue reference model, issues the verdict |
| Tests | `tb/tests/` | `base_test` plus five derived tests |

### Design decisions worth noting

**The driver never reads status flags.** A driver that skips writes when the FIFO
is full cannot test overflow. All policy lives in the generator; all judgement
lives in the scoreboard.

**The monitor triggers on `rd_valid_o`, not `rd_en_i`.** Because the read is
registered, reconstructing the timing by hand would sample the previous read's
data. Trusting the DUT's valid flag makes the monitor independent of read latency.

**The scoreboard's reference model is a queue.** `push_back` on an accepted write,
`pop_front` on an observed read. A queue is a perfect FIFO by definition, so one
comparison checks ordering, data integrity, and no-duplication simultaneously.
Flush clears the model at the same instant the DUT clears itself.

### Testbench versions

Each version is kept to show the progression:

| Version | Demonstrates |
|---|---|
| `tb_v1.sv` | directed, procedural; no interface. Verilator smoke test. |
| `tb_v2.sv` | interface + clocking blocks; class-based driver/monitor/scoreboard |
| `tb_v3.sv` | test classes with inheritance; two agents behind one shared semaphore |
| `tb_v4.sv` | one semaphore per agent — full concurrency |

---

## 3. Testplan

| Test | Requirement | Checks |
|---|---|---|
| `reset_test` | reset produces an empty FIFO | 3 |
| `full_test` | fill to `DEPTH`, `full_o`, FIFO-ordered reads | 7 |
| `flush_test` | flush empties the FIFO and it remains usable | 4 |
| `overflow_test` | write to a full FIFO is rejected, data intact | 5 |
| `underflow_test` | read from an empty FIFO returns no valid data | 5 |
| random traffic | 200 randomised transactions, scoreboard-checked | — |
| two-agent traffic | 50 writes + 50 reads from independent threads | — |

**24 directed checks** plus **125 scoreboard comparisons** per run.

---

## 4. Testcases

```
--- reset ---        empty, !full, occupancy == 0
--- full ---         full_o at DEPTH, reads return 0x11 then 0x22 in order
--- flush ---        empty, occupancy 0, free == DEPTH, reusable afterwards
--- overflow ---     overflow_o pulses, sticky latches, occupancy unchanged,
                     oldest data survives the rejected write
--- underflow ---    underflow_o pulses, sticky latches, rd_valid stays low,
                     occupancy stays 0
```

---

## 5. Coverage

**Questa Altera Starter Edition does not include the `svverification` licence
feature**, which gates `covergroup`, `randomize()`, `randcase`, and `randsequence`:

```
** Error: Failure to checkout svverification license feature.
** Error: (vsim-1) Unable to checkout verification license - required for
   testbench features (randomize, randcase, randsequence, covergroup).
```

The presence of a covergroup blocks elaboration entirely, so coverage is collected
manually in the monitor using a string-keyed associative array. This reproduces
the cross a covergroup would define:

```systemverilog
// cp_occ: coverpoint occupancy_o { bins empty, partial, full; }
// cp_op:  coverpoint {wr_en, rd_en} { bins idle, read, write, simult; }
// cross cp_occ, cp_op;
```

Latest run (`tb_v4`):

```
HIT  empty_write      (4)      empty -> write
HIT  full_read        (11)     full  -> read
HIT  empty_read       (2)      empty -> read   (underflow attempt)
HIT  full_write       (68)     full  -> write  (overflow attempt)
HIT  partial_write    (26)
HIT  partial_read     (11)
HIT  empty_simult     (2)
HIT  partial_simult   (19)
HIT  full_simult      (84)
coverage: 9/9 bins (100.0%)
```

FIFO depth coverage comes from the occupancy histogram, which records how many
cycles the FIFO spent at each fill level. All levels `0..DEPTH` are visited.

**100% is not the whole story.** `empty_read` and `empty_simult` are hit twice
each against 84 for `full_simult` — the traffic mix is write-heavy, so the FIFO
is rarely empty. Two samples is technically covered and practically thin. The
histogram was what made this visible: an earlier run with the weights reversed
produced `occ[0] = 181` and never reached `occ[4]` at all, meaning `full_o` and
overflow went entirely untested while still reporting `TEST PASSED`.

---

## 6. Bugs found

### B1 — Three parameters declared but not implemented

`FWFT_ENABLE`, `OUTPUT_REGISTER_ENABLE`, and `CLEAR_MEMORY_ON_RESET` appear in the
port list and are accepted by the compiler, but nothing in the RTL reads them.
Setting `FWFT_ENABLE = 1` does not produce fall-through behaviour; the read stays
registered. Spec §5's requirement that memory clearing during flush follow
`CLEAR_MEMORY_ON_RESET` is not implemented.

**Status:** found by spec review, not fixed — the RTL is treated as a fixed DUT.

### B2 — Testbench bug: one-cycle pulse sampled a cycle late

The first underflow test failed on `underflow_o` while `underflow_sticky_o`
passed, which proved the DUT had detected the event correctly. `fifo_read`
already advances to the edge where the pulse is visible; the extra `@(cb_mon)`
in the test walked past it. `fifo_write` has one fewer `@`, which is why the
equivalent overflow check passed.

**Status:** fixed. Sticky flags are forgiving, pulses are not — a directed test
must arrive on exactly the right edge, which is one more reason to have a monitor
that samples every edge.

---

## 7. Scoreboard self-test (bug injection)

A checker that has never failed is a checker that hasn't been tested.
`rtl/sync_fifo_with_bug.sv` is a deliberately mutated copy used to prove
detection. Run with `mingw32-make buggy_run`.

| Injected bug | Effect | Caught by |
|---|---|---|
| `BUG_READ_OFFSET` | returns `mem[ptr+1]` instead of `mem[ptr]` | scoreboard: 75 mismatches; 4 directed checks |
| `BUG_PHANTOM_VALID` | asserts `rd_valid_o` on a rejected read | scoreboard: 73 mismatches + 3 "model is empty"; 1 directed check |

**Neither bug tripped the RTL's own assertions.** Those check occupancy bounds,
pointer ranges, and flag consistency — all of which stayed legal while the data
path was broken. Assertions verify structural invariants; the scoreboard verifies
data. Both are needed.

`BUG_PHANTOM_VALID` is the only thing that exercises the scoreboard's
`model_q.size() == 0` branch, which never fires on correct RTL.

---

## 8. Regression results

```
=== 24 passed, 0 failed ===
matched: 125, mismatched: 0
coverage: 9/9 bins (100.0%)
TEST PASSED
```

### Traffic-mix comparison

Two runs, identical DUT and testbench, only the write/read weights changed:

| | write-heavy | read-heavy |
|---|---|---|
| `occ[0]` (empty) | 14 | 181 |
| `occ[4]` (full) | 202 | 2 |
| writes accepted | 135 | 30 |
| overflow exercised | heavily | barely |
| underflow exercised | barely | heavily |

Neither profile alone is sufficient. Each has a blind spot the other covers.

### Lock granularity comparison

| Version | Locking | Sim time | `full_simult` | Scoreboard |
|---|---|---|---|---|
| v3 | one shared semaphore | 3495 ns | 34 | clean |
| v3, lock removed | none | 2995 ns | 84 | clean |
| v4 | one semaphore per agent | 2995 ns | 84 | clean |

All three are correct. The write agent drives `wr_en_i`/`wr_data_i` and the read
agent drives `rd_en_i` — **no shared signal, so no race existed.** The coarse lock
in v3 serialised two operations that never conflicted, costing 500 ns and
50 simultaneous-operation coverage samples for nothing.

A lock is only worth its cost when there is genuine contention. Lock the thing
that is shared, not the thing that contains it.

---

## Tooling

| Tool | Used for |
|---|---|
| Questa Altera Starter Edition 2025.2 | all class-based simulation |
| Verilator | lint, and `tb_v1` smoke test |
| GTKWave / Questa WLF | waveform viewing |

`common/scripts/run.py` wraps compile, elaborate, and run for both simulators.

**Known limitations:**

- No `svverification` licence: no covergroups or constrained randomisation.
  `fifo_txn.sv` retains its `constraint` blocks as documentation of intent; a
  `randomize_manual()` using `$urandom_range` stands in and mirrors the same
  weights. Both become live on a full-licence simulator.
- The licence is single-seat: an open Questa GUI blocks the next command-line run.
- `$urandom` seeds deterministically, so runs are reproducible but always explore
  the same ordering. A real regression would vary the seed.

---

## Repository layout

```
01_fifo_verification/
├── rtl/
│   ├── sync_fifo.sv
│   └── sync_fifo_with_bug.sv     mutated copy, scoreboard self-test only
├── tb/
│   ├── interface/fifo_if.sv
│   ├── txn/fifo_txn.sv
│   ├── agent/
│   │   ├── fifo_driver.sv
│   │   ├── fifo_wr_driver.sv
│   │   ├── fifo_rd_driver.sv
│   │   ├── fifo_monitor.sv
│   │   └── fifo_scoreboard.sv
│   ├── tests/
│   │   ├── base_test.sv
│   │   └── fifo_tests.sv
│   └── top/tb_v1.sv … tb_v4.sv
├── sim/out/                       build artefacts (gitignored)
└── Makefile
```