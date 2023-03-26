# Package

version = "1.1.2"
author = "inv2004"
description = "Monitoring tool with historical snapshots and alerts"
license = "MIT"
srcDir = "src"
bin = @["ttop"]

# Dependencies

requires "nim >= 1.6.12"

requires "illwill"
requires "zippy"
requires "asciigraph"
requires "parsetoml"
requires "https://github.com/inv2004/jsony#non_quoted_key"

const lmDir = "lm-sensors"

task static, "build static release":
  exec "nim -d:release --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c src/ttop.nim"

task staticdebug, "build static debug":
  exec "nim -d:debug --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop-debug c src/ttop.nim"

task bench, "bench":
  exec "nim -d:release --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c -r bench/bench.nim"
