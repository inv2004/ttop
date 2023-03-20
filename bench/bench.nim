import ttop/procfs

import criterion
import jsony
import marshal
import json
import times
import tables
import zippy

proc dumpHook*(s: var string, v: DateTime) =
  s.add '"' & v.format("yyyy-MM-dd hh:mm:ss") & '"'

proc parseHook*(s: string, i: var int, v: var DateTime) =
  var str: string
  parseHook(s, i, str)
  v = parse(str, "yyyy-MM-dd hh:mm:ss")

let str1 = readFile("bench/bench.json")
let info = str1.fromJson(FullInfo)
let str2 = $$info
let str3 = compress(str2)

var cfg = newDefaultConfig()
cfg.budget = 1.0
cfg.minSamples = 10

benchmark cfg:
  # proc jsonySer() {.measure.} =
  #   doAssert jsony.toJson(info).len == 16611

  # proc jsonyDeser() {.measure.} =
  #   doAssert str1.fromJson(FullInfo).pidsInfo.len == 32

  proc jsonSer() {.measure.} =
    doAssert (%info).len == 16611

  proc marshall() {.measure.} =
    doAssert ($$info).len == 51298

  proc unmarshall() {.measure.} =
    doAssert to[FullInfo](str2).pidsInfo.len == 32

  proc uncompress() {.measure.} =
    doAssert uncompress(str3).len == 51298
