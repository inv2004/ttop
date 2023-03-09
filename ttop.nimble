# Package

version = "0.8.7"
author = "inv2004"
description = "Monitoring tool with historical snapshots and alerts"
license = "MIT"
srcDir = "src"
bin = @["ttop"]

# Dependencies

requires "nim >= 1.6.4"

requires "illwill"
requires "zippy"
requires "asciigraph"
requires "parsetoml"

const lmDir = "lm-sensors"

task static, "build static release":
  exec "nim -d:release --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c src/ttop.nim"

task staticdebug, "build static debug":
  exec "nim -d:debug --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop-debug c src/ttop.nim"

