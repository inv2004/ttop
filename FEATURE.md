# IO Graph Feature: Bug Fixes and Improvements

## Summary

The TUI's IO graph view (toggled with `I` key) was non-functional. Multiple
bugs in the data pipeline prevented disk IO from being collected, displayed,
and graphed correctly. This document describes each bug, its root cause, the
fix applied, and the reasoning behind design decisions.

---

## Bug 1: asciigraph crash on all-equal data

**File:** `src/ttop/tui.nim`, proc `graph()`

**Symptom:** When switching to IO view, the graph area displayed
`error in graph: @[0.0]` instead of a plot.

**Root cause:** The `asciigraph` library's `plot()` function crashes when all
data points have the same value (e.g., all `0.0`). At line 54 of asciigraph:

```nim
if int(interval) <= 0:
  l_height = int(interval * pow(10, ceil(-log10(interval))))
```

When `interval = 0.0` (all values identical), `log10(0.0) = -inf`, which throws
a `Defect`. The TUI catches this in the `except CatchableError, Defect` handler
and displays the error message.

This primarily affected IO because `StatV2.io` was frequently zero (see Bug 2
and Bug 3), but could theoretically affect any sort mode during periods of
identical values.

**Fix:** Added an epsilon guard in `graph()` before calling `plot()`:

```nim
if data.len > 0 and min(data) == max(data):
  for i in 0..<data.len:
    data[i] += 0.01
```

This shifts all-equal series by a negligible amount (0.01) so asciigraph gets
a non-zero interval to work with. The visual difference is imperceptible.

**Scope:** Protects all sort modes (CPU, Mem, IO, Pid, Name), not just IO.

---

## Bug 2: Device name mismatch between /proc/mounts and /proc/diskstats

**File:** `src/ttop/procfs.nim`, proc `diskInfo()`

**Symptom:** `Disk.ioUsageRead`, `Disk.ioUsageWrite`, and `Disk.ioUsage` were
always 0 for all disks. The header showed `(rw: 0 / 0)` for every disk. The
IO graph was a flat zero line (compounding Bug 1).

**Root cause:** `diskInfo()` builds its result table from `/proc/mounts`, using
the full device path as the key (e.g., `/dev/nvme0n1p5`). It then parses
`/proc/diskstats` and tries to match device names. But diskstats names lack
the `/dev/` prefix (e.g., `nvme0n1p5`). The check:

```nim
if name notin result:
  continue
```

...always evaluated to true because `"nvme0n1p5" notin {"/dev/nvme0n1p5": ...}`
is true. Every diskstats entry was skipped, so IO fields were never populated
past their `uint` default of 0.

**Fix:** Added key resolution that tries both the bare name and the `/dev/`-
prefixed name:

```nim
let key = if name in result: name
          elif ("/dev/" & name) in result: "/dev/" & name
          else: ""
if key == "":
  continue
```

All subsequent references to `result[name]` and `prevInfo.disk.getOrDefault(name)`
were changed to use `result[key]` and `prevInfo.disk.getOrDefault(key)`.

**Limitations:** LVM/device-mapper devices in `/proc/mounts` have keys like
`/dev/mapper/vg-root`, while `/proc/diskstats` names them `dm-0`. These won't
match and IO stats for such devices remain 0. This is unchanged from the
pre-existing behavior (no regression).

---

## Bug 3: Incorrect scanf field mapping for /proc/diskstats

**File:** `src/ttop/procfs.nim`, proc `diskInfo()`

**Symptom:** Even after fixing Bug 2, IO graph values did not correlate with
actual disk activity. Running IO-heavy commands (`updatedb`, `find /`, `ncdu`)
produced no visible peaks on the graph.

**Root cause:** The scanf pattern was off-by-one, capturing the wrong fields
from `/proc/diskstats`. The kernel documentation defines these fields (after
major/minor/name):

| Field # | Description              | Intended capture | Actually captured |
|---------|--------------------------|------------------|-------------------|
| 4       | reads completed          | tmp              | tmp               |
| 5       | reads merged             | tmp              | tmp               |
| 6       | **sectors read**         | read             | tmp               |
| 7       | time spent reading (ms)  | tmp              | **read**           |
| 8       | writes completed         | tmp              | tmp               |
| 9       | writes merged            | tmp              | tmp               |
| 10      | **sectors written**      | write            | tmp               |
| 11      | time spent writing (ms)  | tmp              | **write**          |
| 12      | I/Os in progress         | tmp              | tmp               |
| 13      | time spent doing I/Os (ms)| (unused)         | **total**          |

The scanf variables were assigned:
```
tmp, tmp, name, tmp, tmp, tmp, read, tmp, tmp, tmp, write, tmp, total
```

The `read` variable captured field 7 (time spent reading in **milliseconds**)
instead of field 6 (sectors read). Similarly, `write` captured field 11 (time
spent writing in ms) instead of field 10 (sectors written). The `total`
variable captured field 13 (time doing I/Os in ms) — this has no meaningful
relationship to disk throughput in bytes.

Since the code multiplies by `SECTOR` (512), these millisecond values were being
treated as sector counts, producing meaningless numbers.

**Fix:** Changed the scanf variable assignments to shift `read` and `write` one
position earlier:

```nim
# Before:
var tmp, read, write, total: int
doAssert scanf(line, "$s$i $s$i ${devName} $i $i $i $i $i $i $i $i $i $i",
    tmp, tmp, name, tmp, tmp, tmp, read, tmp, tmp, tmp, write, tmp, total)

# After:
var tmp, read, write: int
doAssert scanf(line, "$s$i $s$i ${devName} $i $i $i $i $i $i $i $i $i $i",
    tmp, tmp, name, tmp, tmp, read, tmp, tmp, tmp, write, tmp, tmp, tmp)
```

Now `read` = field 6 (sectors read) and `write` = field 10 (sectors written),
which are the correct values for computing disk throughput in bytes.

The `total` variable was removed since the kernel provides no single "total
sectors" field. `Disk.io` is now computed as `ioRead + ioWrite` (total bytes
from read + write sectors):

```nim
# Before:
let io = SECTOR * total.uint
result[name].io = io
result[name].ioUsage = checkedSub(io, prevInfo.disk.getOrDefault(name).io)
let ioRead = SECTOR * read.uint
...

# After:
let ioRead = SECTOR * read.uint
result[key].ioRead = ioRead
result[key].ioUsageRead = checkedSub(ioRead, prevInfo.disk.getOrDefault(key).ioRead)
let ioWrite = SECTOR * write.uint
result[key].ioWrite = ioWrite
result[key].ioUsageWrite = checkedSub(ioWrite, prevInfo.disk.getOrDefault(key).ioWrite)
let io = ioRead + ioWrite
result[key].io = io
result[key].ioUsage = checkedSub(io, prevInfo.disk.getOrDefault(key).io)
```

Note: The `ioRead`/`ioWrite` assignments were moved before `io` so that `io`
can be computed from them. This also changes the order of field population but
has no functional impact.

---

## Bug 4: IO graph displaying raw unscaled bytes

**File:** `src/ttop/tui.nim`, proc `graphData()`

**Symptom:** Even when `StatV2.io` had correct non-zero values, the graph was
practically unreadable. The previous mapping was:

```nim
of Io: result = data.mapIt(float(it.io))
```

This passed raw delta bytes directly to asciigraph. Two problems:

1. **Unscaled magnitude:** `it.io` can be in the billions (bytes), producing
   Y-axis labels that are unreadable in a 4-row terminal graph.

2. **Inconsistent units with formatSPair fix:** An intermediate fix used
   `int(it.io).formatSPair()[0]` (like Mem), but `formatSPair` auto-scales the
   unit — e.g., 524288 bytes → `512.0` (KB), but 2097152 bytes → `2.0` (MB).
   Since the unit label is not rendered on the graph, adjacent data points in
   different units would show `512` next to `2`, misleading the viewer into
   thinking IO dropped when it actually quadrupled.

**Fix:** Changed IO graph to display **throughput in KB/s** — a rate with a
fixed, consistent unit:

```nim
of Io:
  result[0] = data.mapIt(float(it.io) / 1024.0 / refreshSec)
  result[1] = "KB/s"
```

Where `refreshSec = refreshMs.float / 1000.0` is the configured refresh interval
in seconds (defaults to 1.0 from `refreshTimeout` = 1000 ms).

The `graphData` return type was changed from `seq[float]` to
`(seq[float], string)` where the second element is a label string. For all
sort modes except IO, the label is empty (`""`).

In `graph()`, a dim label is rendered next to the LIVE/blog indicator:

```nim
if label.len > 0:
  tb.write " ", styleDim, label, fgNone
```

**Rationale:** KB/s is the standard unit for disk throughput. Using a fixed
unit avoids the unit-hopping problem. The label makes the unit visible. The
refresh interval accounts for different polling rates — if a user configures
`refresh_timeout = 2000`, the per-second rate is still correct because the
delta bytes are divided by 2 seconds.

---

## Data flow summary

The complete pipeline for the IO graph, after all fixes:

```
/proc/diskstats
  └─ diskInfo() in procfs.nim
     ├─ Parses sectors read (field 6) and sectors written (field 10)
     ├─ Converts to bytes: ioRead = sectors_read * 512, ioWrite = sectors_written * 512
     ├─ Computes deltas: ioUsageRead = ioRead - prev.ioRead, ioUsageWrite = ioWrite - prev.ioWrite
     ├─ Computes total: io = ioRead + ioWrite, ioUsage = io - prev.io
     └─ Matches device names with /dev/ prefix fallback
           │
           ▼
genStat() in blog.nim
  └─ StatV2.io = Σ(disk.ioUsageRead + disk.ioUsageWrite) across all disks
     (delta bytes since last snapshot)
           │
           ▼
graphData() in tui.nim
  └─ IO mode: float(it.io) / 1024.0 / refreshSec → KB/s per snapshot
     Label: "KB/s"
           │
           ▼
graph() in tui.nim
  ├─ Epsilon guard (0.01) for all-equal data → prevents asciigraph crash
  ├─ plot(data, width, height=4) → asciigraph rendering
  └─ Label "KB/s" displayed in dim style next to LIVE/blog indicator
```

## Files changed

| File | Changes |
|------|---------|
| `src/ttop/procfs.nim` | Bug 2 (device name matching), Bug 3 (scanf field mapping) |
| `src/ttop/tui.nim` | Bug 1 (epsilon guard), Bug 4 (KB/s scaling + label) |

## No changes to

- `src/ttop/blog.nim` — `StatV2.io` field and `genStat()` are unchanged; they
  already correctly sum `disk.ioUsageRead + disk.ioUsageWrite` (once Bugs 2
  and 3 were fixed, the values flow correctly)
- `src/ttop/format.nim` — no changes needed
- `src/ttop/config.nim` — `refreshTimeout` field was pre-existing; we only
  read it, no changes to config structure
- Data format (`StatV2` binary layout) — no backward compatibility concern;
  the `io` field semantics are unchanged (delta bytes)