import ttop/procfs

import tables
import criterion

var cfg = newDefaultConfig()
cfg.budget = 1.0
cfg.minSamples = 10

let fi = fullInfo()

benchmark cfg:
  proc collectFs() {.measure.} =
    assert fullInfo().pidsInfo.len > 5

  proc sortByChildren() {.measure.} =
    fi.sort(Pid, true)
    assert fi.pidsInfo.len > 5
