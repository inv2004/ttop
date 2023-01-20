# Package

version = "0.3.5"
author = "inv2004"
description = "Monitoring tool with historical snapshots"
license = "MIT"
srcDir = "src"
bin = @["ttop"]


# Dependencies

requires "nim >= 1.6.4"

requires "illwill"
requires "zippy"
requires "asciigraph"
requires "sensors >= 0.2.3"

task dynamic, "build dynamic release":
  exec "nim -d:release -o:ttop-dl c src/ttop.nim"

task static, "build static release":
  exec "nim -d:release --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c src/ttop.nim"

task staticdebug, "build static debug":
  exec "nim -d:debug --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop-debug c src/ttop.nim"

