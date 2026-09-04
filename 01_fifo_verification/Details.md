# SystemVerilog Verification — Learning Notes

Concepts learned building the FIFO verification environment. Each entry covers
what the construct is, where it appears in this project, what it is normally used
for in industry, and the mistakes that are easy to make.

---

# Part 1 — Object-oriented constructs

## 1.1 Class

**What it is.** A blueprint describing data and behaviour. Declaring a class
creates nothing — it only describes what an object of that type will look like.

**In this project.** `fifo_txn` describes a single stimulus item:

```systemverilog
class fifo_txn #(parameter int unsigned DATA_WIDTH = 8);
    rand bit                  wr_en;
    rand bit                  rd_en;
    rand bit [DATA_WIDTH-1:0] wr_data;
    ...
endclass
```

Three fields plus rules about their legal values. It knows nothing about clocks,
pins, or the DUT — that separation is deliberate.

**Normal use.** Every UVM component is a class: `uvm_driver`, `uvm_monitor`,
`uvm_sequence_item`. Classes exist in testbenches because they can be created and
destroyed at runtime, unlike modules which are fixed at elaboration.

**Why classes and not modules.** A module is instantiated once at elaboration and
lives forever at a fixed place in the hierarchy. You cannot create 200 modules on
demand during a test. You can create 200 objects.

### Parameterised classes

`fifo_txn #(8)` and `fifo_txn #(32)` are **different types**. You cannot assign
one to the other. This matters when a class holds a virtual interface, because
`fifo_if #(8,4)` and `fifo_if #(8,16)` are also different types — the class must
be parameterised to match.

---

## 1.2 Object, handle, and the aliasing trap

**The single most important distinction in class-based verification.**

```systemverilog
fifo_txn #(8) t;      // a HANDLE. Points at nothing. Value is null.
t = new();            // NOW an object exists. t holds its address.
```

Declaring `t` allocates no transaction. It creates a pointer. Access `t.wr_en`
before `new()` and the simulator dies:

```
** Fatal: (SIGSEGV) Bad handle or reference.
Fatal error in Function fifo_txn::randomize_manual at fifo_txn.sv line 27
```

The crash happens *inside* the method, at the first field access, because the
call dispatched fine — following the null pointer is what failed.

### Assignment copies the address, never the object

```systemverilog
int x = 5;
int y = x;          // y gets its own copy of 5

fifo_txn a = new();
fifo_txn b = a;     // b and a are THE SAME OBJECT
b.wr_data = 99;     // a.wr_data is now 99 too
```

### The bug this causes

Experiment run during this project:

```systemverilog
t = new();                    // ONE object, created outside the loop
repeat (5) begin
    t.randomize_manual();     // overwrite the same object
    log_q.push_back(t);       // store the same ADDRESS five times
end
```

Output:

```
q[0]: wr_en=0 rd_en=1 wr_data=0x35
q[1]: wr_en=0 rd_en=1 wr_data=0x35
q[2]: wr_en=0 rd_en=1 wr_data=0x35
q[3]: wr_en=0 rd_en=1 wr_data=0x35
q[4]: wr_en=0 rd_en=1 wr_data=0x35
```

Five entries, one object, all showing the last value written.

```
   log_q[0] ──┐
   log_q[1] ──┤
   log_q[2] ──┼──→  [ one object: 0x35 ]
   log_q[3] ──┤
   log_q[4] ──┘
```

**Fix:** move `t = new();` inside the loop. Now each iteration allocates a fresh
object; the old ones still exist and the queue slots still point at them.

**Why it matters at scale.** In a real environment the monitor does:

```systemverilog
forever begin
    @(vif.cb_mon);
    txn.data = vif.cb_mon.rd_data_o;
    mon2sb.put(txn);
end
```

Allocate `txn` once outside the loop and every transaction the scoreboard
receives is the same object. By the time the scoreboard reads them they all hold
the final value, and the scoreboard reports nonsense while the code looks
perfectly reasonable.

**The rule:** allocate a new object every time you hand one to someone else.

---

## 1.3 Constructor and `this`

```systemverilog
function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
             mailbox #(fifo_txn #(DATA_WIDTH))    gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
endfunction
```

`new()` runs once when an object is allocated.

**`this` means "this object's own field."** In the code above there are two things
called `vif`: the class property and the function argument. Without `this`, the
statement `vif = vif` assigns the argument to itself and the property stays null —
producing the null-handle crash on first use.

`this` is only *needed* when a local name shadows a property name. You could name
the argument `vif_in` and skip it. The matching-names-plus-`this` style is
convention because it makes the pairing obvious.

**Normal use.** This pattern is *dependency injection* — the component doesn't
go looking for its interface or mailbox, they're handed to it at construction.
UVM does the same thing through the config DB.

---

## 1.4 Inheritance

**What it is.** A class extends another and gets all its properties and methods
without redeclaring them.

**In this project.** All five tests share the same DUT-poking tasks and the same
pass/fail bookkeeping:

```systemverilog
class base_test #(...);
    virtual fifo_if #(DATA_WIDTH, DEPTH) vif;
    int pass_count, fail_count;

    virtual task run(); ... endtask
    task automatic check(string label, bit condition); ... endtask
    task automatic fifo_write(...); ... endtask
    task automatic fifo_read(...);  ... endtask
    task automatic fifo_flush();    ... endtask
    task automatic do_reset();      ... endtask
endclass

class reset_test #(...) extends base_test #(DATA_WIDTH, DEPTH);
    function new(string name, virtual fifo_if #(...) vif,
                 fifo_scoreboard #(DATA_WIDTH) sb);
        super.new(name, vif, sb);        // MUST call the parent constructor
    endfunction

    virtual task run();
        do_reset();                       // inherited, no definition needed here
        check("empty after reset", vif.cb_mon.empty_o);
        ...
    endtask
endclass
```

`reset_test::run()` calls `do_reset()` and `check()` with no definition in sight,
because it inherited them.

**`super.new(...)`** runs the parent constructor. It's what fills in `vif`, `sb`,
and `name`. Omit it and you get a compile error, or a null `vif`.

**The practical motivation.** Not architectural purity — five tests all need
`fifo_write` and you don't want to write it five times.

**Normal use.** UVM is built entirely on this. `uvm_object` → `uvm_transaction` →
`uvm_sequence_item` → your transaction. Every layer adds a little and inherits
the rest.

---

## 1.5 Virtual methods and polymorphism

**This is the concept most worth understanding properly.**

### What polymorphism means

*Many forms.* A single handle type can point at objects of several different
derived types, and calling a method on it runs the version belonging to the
**actual** object, not the declared type.

### Where it is used in this project

The top module holds tests in a queue typed as the **base** class:

```systemverilog
base_test #(DATA_WIDTH, DEPTH) tests[$];    // ← BASE type, deliberately

tests.push_back(t_reset);        // a reset_test
tests.push_back(t_full);         // a full_test
tests.push_back(t_flush);        // a flush_test
tests.push_back(t_ovf);          // an overflow_test
tests.push_back(t_unf);          // an underflow_test

foreach (tests[i]) begin
    $display("--- %s ---", tests[i].name);
    tests[i].run();              // ← runs the DERIVED version each time
end
```

`tests[i]` is a `base_test` as far as the compiler is concerned. Five different
derived types go in; one loop calls `run()`; five different behaviours come out.

### The experiment that proves it

Remove one keyword from `base_test`:

```systemverilog
virtual task run();     →     task run();
```

Result:

```
base_test::run() -- nothing to do          (x5)
=== 0 passed, 0 failed ===
TEST PASSED
1070 DUT assertion errors
```

Every call dispatched to the **empty base version**. Because `reset_test::run()`
never ran, `do_reset()` was never called, `rst_ni` stayed `X` for the whole
simulation, and every DUT assertion fired every cycle.

### Why

| | Binding | Uses |
|---|---|---|
| non-virtual | compile time | the **declared** type of the handle |
| `virtual` | runtime | the **actual** type of the object |

Without `virtual`, the compiler sees `base_test tests[$]`, binds to
`base_test::run()`, and never looks again. With `virtual`, the lookup happens at
runtime through the object's own method table.

### The secondary lesson

**The simulation still printed `TEST PASSED`.** Zero tests ran, zero checks
executed, the DUT was never reset — and the verdict line said everything was fine.
Only the DUT's own assertions revealed the problem.

Hence the guard that was added:

```systemverilog
if (total_pass + total_fail == 0)
    $fatal(1, "No checks executed -- test suite did not run");
```

A passing testbench that runs no tests looks identical to one that runs all of
them unless you check that the expected work actually happened.

### Normal use in industry

This is how every test framework selects behaviour at runtime:

```systemverilog
// UVM: the base handle is uvm_test, the actual object is chosen by a plusarg
run_test();   // +UVM_TESTNAME=my_overflow_test
```

The infrastructure calls `run_phase()` on a `uvm_test` handle. Polymorphism makes
the right test execute. Same pattern in sequences, drivers, and scoreboards —
extend, override, and the framework calls your version.

Also used for `copy()`, `compare()`, `convert2string()` — a base handle prints
itself correctly regardless of what it actually is.

---

# Part 2 — Connecting classes to hardware

## 2.1 Interface

**What it is.** A named bundle of signals that can be instantiated into the design
hierarchy, like a module.

**In this project.** `fifo_if` bundles all 18 DUT signals plus the clock:

```systemverilog
interface fifo_if #(parameter DATA_WIDTH = 8, parameter DEPTH = 4)
                   (input logic clk_i);
    logic rst_ni;
    logic wr_en_i;
    logic [DATA_WIDTH-1:0] wr_data_i;
    ...
```

**Why bother.** Without it, every testbench component needs 18 ports and every
connection is 18 lines. With it, one handle carries everything.

**Normal use.** Standard for any protocol — `axi_if`, `apb_if`, `spi_if`. A
verification IP ships with its interface, and connecting it to a new DUT is one
instantiation instead of dozens of wires.

---

## 2.2 Clocking block

**What it solves.** Race conditions between testbench and DUT.

The naive approach:

```systemverilog
@(negedge clk_i);        // drive half a cycle early
wr_en_i = 1'b1;
@(posedge clk_i);        // DUT samples here
#1;                      // wait for outputs to settle
assert (!overflow_o);
```

That works, but the timing convention lives in your head and in every task.
Write one task that drives on `posedge` instead and the testbench changes a signal
at the exact instant the DUT samples it. Whether the DUT sees old or new depends
on simulator event ordering — a bug that passes on one tool and fails on another.

**The clocking block makes the convention declarative:**

```systemverilog
clocking cb_drv @(posedge clk_i);
    default input #1step output #1ns;
    output wr_en_i, wr_data_i, rd_en_i, flush_i;
    input  full_o, empty_o, occupancy_o;
endclocking
```

### The two rules

```
                        posedge clk_i
                              │
     sample all inputs  ──────┤────── drive all outputs
     (#1step BEFORE)          │       (#1ns AFTER)
```

**Sample early, drive late.** The TB and DUT are never active at the same instant,
so no race is possible.

### `#1step`

The simulator's time precision — 1 ps under `` `timescale 1ns/1ps ``. But think of
it as *"the smallest possible moment before the edge"*, not as a duration.

That is exactly the value the DUT's own flip-flops latched. Your monitor sees what
the hardware saw.

Don't write `#1ps` instead: it isn't portable across timescales, and `1step`
refers to a dedicated scheduling region (the preponed region) that the LRM
guarantees is race-free. `1step` is only legal as an *input* skew.

### Direction is from the testbench's point of view

This inverts against the signal names and confuses everyone once:

| Signal | DUT sees it as | Clocking block declares it |
|---|---|---|
| `wr_en_i` | input | `output` |
| `full_o` | output | `input` |

Every `_i` becomes `output`, every `_o` becomes `input`. If that pattern is
broken, something is wrong.

### The one-edge lag

**A value updated by edge N is readable at edge N+1.**

```
            edge 3                    edge 4
              │                          │
   sample ────┤                sample ───┤
   (reads 0)  │                (reads 1) │
occupancy_o ──┴──────── 1 ───────────────┴──── 1 ──
     0        ↑
              flop updates here
```

The sample point sits on the **left** of the edge; the flop output appears on the
**right**. This is why a check immediately after `fifo_write` reads the old
occupancy and needs one extra `@(fif.cb_mon)`.

It applies uniformly to every signal, so relative timing between signals is
preserved — the whole snapshot is just shifted one cycle from the waveform.

### `<=` versus `=`

```systemverilog
fif.cb_drv.wr_en_i <= 1'b1;    // clocking output: SCHEDULED drive, use <=
fif.rst_ni          = 1'b0;    // raw interface signal: immediate, use =
```

Assigning to a clocking output is not an assignment, it is *recording what the
signal should become at the next drive point*. There is one slot per signal, and
**the last write before the edge wins**:

```systemverilog
fif.cb_drv.wr_en_i <= 1'b0;   // slot := 0
fif.cb_drv.wr_en_i <= 1'b1;   // slot := 1   (overwrites; the 0 never happened)
```

This explains why back-to-back writes show `wr_en_i` continuously high: each
task's trailing deassert is overwritten by the next task's assert before the
drive point. The deassert is a *safe default*, not a guaranteed deassert.

---

## 2.3 Modport

**What it is.** A directional view of an interface — same signals, restricted
access, defined per role.

```systemverilog
modport DRV (clocking cb_drv, output rst_ni, input clk_i);
modport MON (clocking cb_mon, input  rst_ni, input clk_i);
modport DUT (input clk_i, rst_ni, wr_en_i, ...
             output full_o, empty_o, ...);
```

**Two jobs:** access control (wrong-direction access becomes a compile error
instead of a silent multiple-driver bug) and documentation (three roles, visible
at a glance).

**Note what is and isn't declared.** `clocking cb_drv` imports the whole bundle
including directions — repeating those members would be illegal. Only `rst_ni` and
`clk_i` need explicit directions, because they aren't clocking members.

**Why `rst_ni` sits outside the clocking blocks.** Reset is asynchronous in this
DUT (`always_ff @(posedge clk_i or negedge rst_ni)`). Routing it through a
synchronous adapter would make mid-cycle assertion impossible.

**Honest caveat.** In this project the modports are largely documentation. The DUT
connects signal-by-signal (keeping the RTL interface-agnostic), and class-based
components hold a plain `virtual fifo_if` without a modport, which is the common
industry practice. The real guardrail is that **`cb_mon` has no `output` members at
all**, so a monitor structurally cannot drive.

---

## 2.4 Virtual interface

**The bridge between classes and hardware.**

An interface is instantiated into the static design hierarchy. A class is a
runtime object with no hierarchical path. A class body cannot see the name `fif`
declared in the module — different scopes entirely.

```systemverilog
class fifo_driver #(...);
    virtual fifo_if #(DATA_WIDTH, DEPTH) vif;    // handle to an interface

    function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif, ...);
        this.vif = vif;
    endfunction

    task drive(...);
        vif.cb_drv.wr_en_i <= t.wr_en;           // now it reaches real pins
    endtask
endclass
```

The module passes its interface in at construction:

```systemverilog
drv = new(fif, gen2drv);
```

**Naming warning.** `virtual` here means "a handle to an interface instance." It
has nothing to do with virtual *methods*. Same keyword, unrelated job.

**Normal use.** Universal. In UVM the virtual interface is stored in the config DB
at the top level and retrieved by each component — same idea, more machinery.

---

# Part 3 — Concurrency

## 3.1 `fork ... join_none`

```systemverilog
fork
    mon.run();
    sb.run_writes();
    sb.run_reads();
join_none
```

Launches three background threads and continues immediately.

**Why `join_none` and not `join`.** All three tasks are `forever` loops that never
return. `join` would wait for them, and the test would hang forever.

| Form | Waits for |
|---|---|
| `join` | all threads |
| `join_any` | the first to finish |
| `join_none` | nothing — fire and continue |

**Normal use.** How every persistent verification component is started. In UVM the
phasing infrastructure does this for you.

---

## 3.2 Mailbox

**What it is.** A thread-safe, typed queue for passing objects between concurrent
processes, with blocking semantics.

**In this project.** Three of them:

```systemverilog
mailbox #(fifo_txn #(DATA_WIDTH)) gen2drv;      // generator → driver
mailbox #(bit [DATA_WIDTH-1:0])   mon2sb_wr;    // monitor → scoreboard (writes)
mailbox #(bit [DATA_WIDTH-1:0])   mon2sb_rd;    // monitor → scoreboard (reads)
```

The driver's entire life:

```systemverilog
task automatic run();
    fifo_txn #(DATA_WIDTH) t;
    forever begin
        gen2drv.get(t);      // BLOCKS if the mailbox is empty
        drive(t);
    end
endtask
```

### The blocking behaviour is the point

If the mailbox is empty, `get()` **suspends the thread** — not spinning, not
polling, genuinely asleep and consuming nothing. When someone calls `put()`, the
simulator wakes it.

That is what a mailbox gives you over a plain queue. A queue would need
`wait (q.size() > 0)` and manual synchronisation.

### The full method set

| Method | Behaviour |
|---|---|
| `get(t)` | blocks until an item is available |
| `try_get(t)` | returns 0 immediately if empty |
| `put(t)` | blocks if the mailbox is *full* (bounded only) |
| `try_put(t)` | returns 0 immediately if full |
| `peek(t)` | blocking, but leaves the item in place |
| `num()` | how many items are queued |

`new()` is unbounded — `put()` never blocks. `new(4)` caps it at four, which
creates back-pressure on the producer.

### A trap with `try_get`

```systemverilog
forever begin
    if (gen2drv.try_get(t)) drive(t);
    else @(vif.cb_drv);          // ← REQUIRED
end
```

Without a time-consuming statement in the else branch, `forever` spins infinitely
at the same simulation timestamp and hangs the simulator.

### Why `put()` needed a companion signal

`put()` returns instantly. After the generator's 200 `put()` calls, the driver has
barely started. Without waiting, the test would reach `$finish` with ~190
transactions still queued — hence `drive_count` and later the `all_done` event.

---

## 3.3 Event

**What it is.** A pure notification. No data, no queue — one process signals,
another wakes.

**In this project.** Replaced a polling wait:

```systemverilog
wait (drv.drive_count == 200);      // before: re-evaluated on every change
wait (drv.all_done.triggered);      // after:  sleeps until signalled
```

Driver side:

```systemverilog
event all_done;
int   target_count;          // 0 = run indefinitely

task automatic run();
    forever begin
        gen2drv.get(t);
        drive(t);                             // drive_count++ inside
        if (target_count > 0 && drive_count == target_count)
            -> all_done;                      // fire, once
    end
endtask
```

`target_count` is a fixed goal set before the driver starts. `drive_count` is what
increments. The event fires on the one transaction where they match.

The `target_count > 0` guard matters: without it, an unset target of 0 would match
`drive_count == 0` and signal "done" before anything happened.

### The trap: events have no memory

If the trigger fires **before** you reach `@(all_done)`, you miss it and hang
forever.

```systemverilog
@(drv.all_done);                    // misses a trigger that already happened
wait (drv.all_done.triggered);      // safe — .triggered stays true for the
                                    // rest of the current time step
```

This project uses `.triggered` for that reason.

**Normal use.** Cross-component synchronisation: "reset is complete", "the test is
finished", "the DUT raised an interrupt". UVM wraps the same idea in
`uvm_event`, which adds data passing and a proper trigger history.

---

## 3.4 Semaphore

**What it is.** A counted lock. `new(1)` makes it a mutex.

```systemverilog
semaphore s = new(1);   // one token
s.get(1);               // take a token — BLOCKS if none available
s.put(1);               // return it, waking whoever waits
```

**In this project.** Two independent agents share one interface:

```systemverilog
task automatic run();            // fifo_wr_driver
    repeat (n_writes) begin
        bus_sem.get(1);                      // claim the bus
        vif.cb_drv.wr_en_i   <= 1'b1;
        vif.cb_drv.wr_data_i <= $urandom_range(8'h01, 8'hFE);
        @(vif.cb_drv);                       // token held ACROSS the edge
        vif.cb_drv.wr_en_i   <= 1'b0;
        bus_sem.put(1);                      // release
        drive_count++;
    end
    -> done;
endtask
```

### What one shared token does

```
              cycle 1        cycle 2        cycle 3        cycle 4
 token:        [WRITE]        [READ]        [WRITE]        [READ]
 wr_en_i    ─────1──────────────0──────────────1──────────────0───
 rd_en_i    ─────0──────────────1──────────────0──────────────1───
 wr agent:   RUNNING          asleep         RUNNING        asleep
 rd agent:    asleep         RUNNING          asleep       RUNNING
```

The `@(vif.cb_drv)` sits *inside* the locked region, so the token is held across
the clock edge. The other agent is asleep for that whole span — including the
edge — so **simultaneous read/write becomes impossible.**

### The measured cost

| Version | Locking | Sim time | `full_simult` coverage | Scoreboard |
|---|---|---|---|---|
| v3 | one shared semaphore | 3495 ns | 34 | clean |
| v3, lock removed | none | 2995 ns | 84 | clean |
| v4 | one semaphore per agent | 2995 ns | 84 | clean |

All three correct. The coarse lock cost 500 ns and 50 coverage samples.

### The actual lesson

Ask what the agents are really fighting over:

```
write agent touches:  wr_en_i, wr_data_i
read agent touches:   rd_en_i
                      ─────────────────
                      no overlap
```

**Nothing.** They never write the same signal, and each clocking output has its
own scheduling slot. There was no race to prevent — which is why removing the lock
entirely changed nothing.

**Lock the thing that is shared, not the thing that contains it.** A defensive
lock added without checking what is actually contended is a real and common
mistake, and it costs both performance and coverage.

**When you would genuinely need it here:** if both agents drove `wr_data_i`, or if
a third agent drove `flush_i` while another read it to make decisions. Shared
*state*, not shared *bundle*.

**Normal use.** Modelling limited resources: a bus with N masters, a memory
controller with N outstanding transactions, an arbiter. `new(4)` for a pool of
four.

---

# Part 4 — Data structures

## 4.1 Queue

```systemverilog
bit [DATA_WIDTH-1:0] model_q[$];    // [$] makes it a queue
```

A dynamically-sized ordered list.

| Method | Effect |
|---|---|
| `push_back(x)` | add to the end |
| `push_front(x)` | add to the front |
| `pop_front()` | remove from the front, return it |
| `pop_back()` | remove from the end, return it |
| `size()` | element count |
| `delete()` | empty it |
| `q[0]` | peek without removing |

**In this project — the entire reference model:**

```systemverilog
// on an accepted write
model_q.push_back(d);

// on an observed read
expected = model_q.pop_front();
if (observed !== expected) $error("expected 0x%02h, got 0x%02h", expected, observed);

// on flush
model_q.delete();
```

**Why a queue is the perfect FIFO model.** `push_back` + `pop_front` *is* FIFO
behaviour by definition, so the model cannot itself have an ordering bug.
Comparing against it checks three properties at once:

- **ordering** — wrong order means `pop_front` returns a different value
- **data integrity** — corrupted bits mismatch
- **no duplication or loss** — a duplicate read empties the model early and hits
  the `size() == 0` branch

That last branch caught the injected `BUG_PHANTOM_VALID`:

```
SCOREBOARD: read produced 0x04 but model is empty
```

**Normal use.** Reference models, delay lines, outstanding-transaction tracking,
any scoreboard for an in-order interface.

---

## 4.2 Dynamic array

```systemverilog
string required[] = '{ "empty_write", "full_read", ... };
```

Sized at runtime rather than at compile time. `new[n]` allocates, `size()` reports,
`delete()` frees.

**In this project.** The coverage report's list of required bins, and the
transaction log. Used where the element count isn't known when the code is
written.

**Difference from a queue.** A dynamic array is sized in one operation and indexed
like a normal array. A queue grows and shrinks element by element. Use an array
when you know the size up front, a queue when items arrive over time.

---

## 4.3 Associative array

```systemverilog
int occ_hist[int];        // int key, int value
int cov_bins[string];     // string key
```

A lookup table with no fixed size. Entries spring into existence when first
written — think labelled boxes drawn on demand, not a fixed row of slots.

**In this project — the occupancy histogram:**

```systemverilog
always @(fif.cb_mon) begin
    int occ;
    if (fif.rst_ni === 1'b1) begin
        occ = fif.cb_mon.occupancy_o;
        if (!occ_hist.exists(occ))          // check without creating
            occ_hist[occ] = 0;
        occ_hist[occ] = occ_hist[occ] + 1;
    end
end
```

One tally per clock edge, into the box matching the current fill level. The counts
only ever grow and always sum to the number of cycles sampled — it is a **logbook
of where the FIFO has been**, not a gauge of where it is now.

### Why `.exists()`

`occ_hist[k]++` means "read, add one, write back." The read fails the first time a
key is used, because the key doesn't exist yet:

```
** Warning: (vsim-3829) Non-existent associative array entry. Returning default value.
```

`.exists(key)` tests for a key **without creating it**.

### Methods

| Method | Effect |
|---|---|
| `exists(k)` | is this key present? |
| `delete(k)` | remove one entry |
| `num()` / `size()` | how many entries |
| `first(k)` / `next(k)` | iterate |
| `foreach (a[i])` | visit every *existing* key |

`foreach` only visits keys that exist — which is why a missing box produces no
output line at all.

### What it revealed

```
occ[0] = 19,  occ[1] = 10,  occ[2] = 4,  occ[3] = 2
                                     ← no occ[4] at all
```

Box 4 was never created, meaning occupancy never reached `DEPTH`. Consequently
`full_o` never asserted and `overflow_event` could never fire — **four testplan
items silently untested, while the run reported `TEST PASSED`.**

Reversing the traffic weights produced `occ[4] = 143` and made those cases live.

**This is the same question functional coverage answers**, done by hand. The
histogram converts "I ran some random stimulus" into "here is exactly which DUT
states I visited and how often."

**Normal use.** Sparse memory models, scoreboards keyed by transaction ID or
address, per-test statistics, coverage collection when covergroups aren't
available.

---

# Part 5 — Randomisation (licence-blocked)

Questa Altera Starter Edition lacks the `svverification` licence feature:

```
** Error: (vsim-1) Unable to checkout verification license - required for
   testbench features (randomize, randcase, randsequence, covergroup).
```

The constructs below are written into `fifo_txn.sv` as documentation of intent and
become live on a full-licence simulator. `randomize_manual()` using
`$urandom_range` stands in.

## 5.1 `rand` and `randomize()`

```systemverilog
rand bit [DATA_WIDTH-1:0] wr_data;
```

`rand` marks a field as solver-controlled. Fields without it are untouched by
`randomize()`.

```systemverilog
if (!t.randomize()) $error("randomize failed");
```

**`randomize()` returns 0 if the constraints are unsatisfiable, and silently
leaves the fields unchanged.** Always check the return, or write `void'()` to
state explicitly that you're not.

**`bit`, not `logic`.** Stimulus should never be unknown — you want to drive
definite values. `logic` is for observing the DUT, where `X` carries information.

## 5.2 `constraint` and `inside`

```systemverilog
constraint c_data { wr_data inside {[8'h01:8'hFE]}; }
```

A constraint is a **declaration**, not procedural code. It states what must be true
after randomisation.

`inside {[a:b]}` is inclusive set membership. It extends to discrete sets:
`inside {1, 5, [10:20], 99}`.

Here, `0x00` and `0xFF` are excluded so they remain unambiguous sentinels in
waveforms and logs.

## 5.3 `dist`

```systemverilog
constraint c_mix {
    wr_en dist {1 := 70, 0 := 30};
    rd_en dist {1 := 40, 0 := 60};
}
```

`inside` says which values are **legal**. `dist` says how **often** each occurs.

Think of a bag of tickets: 70 saying 1, 30 saying 0. Weights are relative, not
percentages — `{1:=7, 0:=3}` is identical.

`:=` gives each listed value that weight individually. `:/` splits the weight
across a range.

### Why it matters here

The two coins are independent, so all four combinations occur naturally:

| `wr_en` | `rd_en` | Roughly | Tests |
|---|---|---|---|
| 1 | 1 | 28% | simultaneous read/write |
| 1 | 0 | 42% | write only |
| 0 | 1 | 12% | read only |
| 0 | 0 | 18% | idle |

Simultaneous read/write — a testplan item — happens 28% of the time for free.

**And the ratio steers which corners you reach.** Writes outpacing reads fills the
FIFO and exercises `full_o` and overflow; the reverse drains it and exercises
underflow. This project measured both:

| | write-heavy | read-heavy |
|---|---|---|
| `occ[0]` | 14 | 181 |
| `occ[4]` | 202 | 2 |

Neither profile alone is adequate.

## 5.4 `solve before`

```systemverilog
rand int unsigned burst_len;
rand bit [DW-1:0] payload[];
constraint c_size { payload.size() == burst_len; }
constraint c_ord  { solve burst_len before payload; }
```

Controls **solver ordering**. Without it the solver picks `burst_len` and
`payload.size()` jointly, and the length distribution skews toward whatever is
cheapest to satisfy. `solve before` forces `burst_len` to be chosen first, then
the payload sized to match.

The way to see it: histogram `burst_len` over 1000 randomisations with and without
the `solve`.

## 5.5 The stand-in

```systemverilog
function void randomize_manual();
    wr_data = $urandom_range(8'h01, 8'hFE);      // mirrors c_data
    wr_en   = ($urandom_range(1, 100) <= 70);    // mirrors c_mix
    rd_en   = ($urandom_range(1, 100) <= 40);
endfunction
```

`$urandom_range` needs no licence feature. Writing the weighting by hand shows
exactly what `dist` does under the hood.

**Caveat:** `$urandom` seeds deterministically, so runs are reproducible but always
explore the same ordering. Real regressions vary the seed.

---

# Part 6 — Verification methodology

## 6.1 The separation of concerns

| Component | Question it answers | Knows nothing about |
|---|---|---|
| Generator | *What* should we try? | pins, timing |
| Driver | *How* do I put that on wires? | correctness |
| Monitor | *What* actually happened? | intent |
| Reference model | What *should* have happened? | pins |
| Scoreboard | Do those match? | how it was driven |

### Why not just check inside the driver?

The obvious instinct is to add a check to `drive_txn`. Try it and you discover:

**You don't know the expected value.** You wrote `0x9B` this cycle, but the FIFO
returns the *oldest* item — written eleven cycles ago. Knowing it requires a
history of every accepted write, which is a reference model.

**Acceptance is conditional.** `write_accept = wr_en_i && (!full_o || read_accept)`.
The "occupancy grew" check becomes "grew, unless full, unless a read was also
accepted, unless..." — you end up reimplementing the DUT's acceptance logic inside
the driver, and it has to be right or your checks lie.

**Timing.** `rd_data_o` appears one cycle after acceptance, so the driver would
have to linger — which destroys its ability to drive back-to-back transactions.

**Ordering is invisible.** "Did items come out in the order they went in" is a
property of the *stream*, not of any single transaction. A task that sees one
transaction and returns structurally cannot observe it.

**Push through all of that and you have written a scoreboard — badly, and tangled
with the driver.**

**The rule:** anything that needs to remember the past belongs outside the driver.
Driving is stateless. Checking is inherently stateful.

### The driver must not judge

```systemverilog
if (!vif.cb_drv.full_o)          // ← never do this
    vif.cb_drv.wr_en_i <= t.wr_en;
```

Legal, reasonable-looking, and it makes overflow untestable. In this project ~60
overflow events and a passing overflow test all depended on the driver blindly
pushing writes into a full FIFO.

---

## 6.2 Intent versus outcome

Measured in this project:

```
transactions driven:   200
writes driven:         ~140  (70% weight)
writes ACCEPTED:        81
```

Roughly 60 writes were driven and silently rejected because the FIFO was full.

A log of what the generator *intended* would expect ~140 items to come out. The
monitor recorded 81. **A scoreboard fed from intent would report catastrophic
failure on a perfectly correct DUT.**

That gap is the entire justification for having a monitor. It records what
happened on the pins, not what was requested.

---

## 6.3 Trust the valid flag

The read is registered, so `rd_data_o` appears one cycle after acceptance.

```systemverilog
// WRONG — reconstructs the timing, reads the previous read's data
if (rd_en_i && !empty_o) capture(rd_data_o);

// RIGHT — the DUT tells you when its output is valid
if (rd_valid_o) capture(rd_data_o);
```

The DUT flops `rd_data_o` and `rd_valid_o` together, so sampling on the flag gives
you a consistent pair regardless of latency. **Don't reconstruct timing you can
observe** — this also means the monitor keeps working if `FWFT_ENABLE` or the
output register configuration ever changes.

---

## 6.4 Assertions versus scoreboards

Both injected bugs were caught by the scoreboard. **Neither tripped the RTL's own
assertions.**

| | Verifies | Example |
|---|---|---|
| RTL assertions | structural invariants | occupancy ≤ DEPTH, pointers in range, flags match occupancy |
| Scoreboard | data correctness | right values, right order, none lost or duplicated |

`BUG_READ_OFFSET` returns `mem[ptr+1]`. Every counter stays legal, every pointer
stays in range, every flag matches occupancy — the structure is perfect and the
data is garbage. The assertions had nothing to complain about.

**They cover different surfaces. You need both.**

---

## 6.5 Bug injection

A checker that has never failed is a checker that has not been tested.

| Injected bug | Effect | Scoreboard | Directed |
|---|---|---|---|
| `BUG_READ_OFFSET` | returns `mem[ptr+1]` | 75 mismatches | 4 checks |
| `BUG_PHANTOM_VALID` | `rd_valid_o` on a rejected read | 73 mismatches + 3 "model is empty" | 1 check |

Two observations:

**The scoreboard caught 75 where directed tests caught 4.** Same bug, same run.
The directed tests only check the three specific values they know about; the
scoreboard checks every read that happens.

**`BUG_PHANTOM_VALID` is the only thing that exercises the `model_q.size() == 0`
branch**, which never fires on correct RTL. Without injecting it, that code path
would have been dead and unverified.

---

## 6.6 Directed versus random

| | Directed | Random |
|---|---|---|
| Purpose | prove specific requirements | explore unimagined combinations |
| Volume | ~20 focused tests | millions of cycles |
| Checking | inline, hand-written | scoreboard, automatic |
| Debug | easy, deterministic | needs seed reproduction |
| Finds | bugs you predicted | bugs you didn't |

**Directed tests only find bugs you thought to look for.** Random traffic explores
combinations you would never write by hand.

**But random stimulus without a scoreboard is just noise.** For a while this
project drove 200 random transactions with nothing checking them — data went in,
data came out, nobody looked. The run reported `TEST PASSED` regardless.

**And random does not automatically reach interesting states.** Twenty random
transactions never filled the FIFO. Four writes in a row — a directed sequence —
gets there reliably.

Keep both. Directed tests are your requirement checklist and map to spec clauses;
random is your bug hunt.

---

## 6.7 Reading coverage properly

```
coverage: 9/9 bins (100.0%)
```

Looks finished. Then look at the counts:

```
empty_read       (2)
empty_simult     (2)
full_simult     (84)
```

**A bin hit twice is technically covered and practically thin.** Two samples will
not shake out a corner-case bug. The write-heavy traffic mix means the FIFO is
rarely empty, so operations *at* empty barely happen.

A coverage percentage without the distribution behind it is misleading. This is
why regressions run multiple seeds and weightings.

---

# Part 7 — Smaller things worth remembering

## `===` versus `==`

```systemverilog
if (fif.rst_ni === 1'b1)     // 4-state compare: X and Z compare literally
if (fif.rst_ni == 1'b1)      // returns X if either side is unknown
```

`==` against an unknown returns `X`, which makes an `if` behave unpredictably.
Use `===` whenever a signal might be `X` — reset checks, monitor guards.

**Related trap:** `disable iff (!rst_ni)` does **not** protect you at time 0,
because `rst_ni` is `X` there, not 0. `X` is not `!rst_ni`, so the disable never
engages and every assertion fires. This produced 100 spurious errors when the
random loop accidentally ran before reset.

## `$display` format strings

```systemverilog
$display(cond ? "PASSED" : "FAILED");         // prints 101877149276638314029598020
$display("%s", cond ? "PASSED" : "FAILED");   // prints PASSED
```

With a single non-literal argument, `$display` treats it as a value to format, not
a format string.

## Declarations at the top of a block

SystemVerilog requires all declarations before any statements in a `begin/end`.
Putting `fifo_txn t;` forty lines into an `initial` block is a syntax error. Wrap
a sub-block in `begin/end` if you need locals mid-procedure.

## `task` versus `function`

A `function` must complete in zero simulation time. Anything containing `@(...)`
or `#delay` must be a `task`. **If it waits, it's a task.**

## `automatic`

```systemverilog
task automatic drive(fifo_txn t);
```

Gives each call its own copy of local variables. Without it, concurrent calls
share storage and corrupt each other. Free insurance; make it a habit.

## `include` versus separately compiled files

Class files that are `` `include``d must **not** also be passed to the compiler —
that produces duplicate definitions. Include paths need `+incdir+`, and compile
order matters: a class must be declared before another class extends it or names
it as a type.

For forward references between classes:

```systemverilog
typedef class fifo_scoreboard;   // "this class exists, details later"
```

The scalable answer is a package, which fixes the ordering in one place:

```systemverilog
package fifo_pkg;
    `include "fifo_txn.sv"
    `include "fifo_scoreboard.sv"
    `include "fifo_monitor.sv"
endpackage
```

## VCD cannot represent interfaces or class objects

VCD is a 1995-era format that only knows modules and nets. Interfaces (2005) and
class objects have no representation. Questa's native WLF handles both. For a
class-based environment, use `vsim -view` rather than GTKWave.

## Pulses versus sticky flags

`overflow_o` and `underflow_o` are one-cycle pulses. **A pulse is only catchable on
exactly one edge.** A directed test must arrive at precisely the right moment; the
monitor, sampling every edge, cannot miss it.

This caused a real testbench bug: `fifo_read` contains one more `@` than
`fifo_write`, so an extra `@(cb_mon)` that worked for the overflow check walked
past the underflow pulse. The sticky flag passing while the pulse failed was the
clue that the DUT was fine and the test was wrong.

---

# Appendix — Concept to location map

| Concept | Where it lives |
|---|---|
| class, object | `tb/txn/fifo_txn.sv` |
| handle aliasing | experiment in `tb_v2.sv` |
| inheritance, `super.new` | `tb/tests/fifo_tests.sv` |
| polymorphism, `virtual` | `base_test::run()` + the `tests[$]` loop |
| interface, clocking block, modport | `tb/interface/fifo_if.sv` |
| virtual interface | every class in `tb/agent/` |
| mailbox | `gen2drv`, `mon2sb_wr`, `mon2sb_rd` |
| event | `fifo_driver::all_done` |
| semaphore | `fifo_wr_driver`, `fifo_rd_driver` |
| queue | `fifo_scoreboard::model_q` |
| dynamic array | `fifo_monitor::report_coverage()` |
| associative array | `occ_hist`, `cov_bins` |
| constraint, `inside`, `dist` | `fifo_txn.sv` (licence-blocked) |
| `fork/join_none` | `tb_v3.sv`, `tb_v4.sv` |