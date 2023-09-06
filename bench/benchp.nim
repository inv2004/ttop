import ttop/procfs

import tables
import criterion

var cfg = newDefaultConfig()
cfg.budget = 1.0
cfg.minSamples = 10

benchmark cfg:
  proc jsonSer() {.measure.} =
    assert fullInfo().pidsInfo.len > 5
