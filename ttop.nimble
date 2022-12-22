# Package

version = "0.3.3"
author = "alexander"
description = "Monitoring tool with historical snapshots"
license = "MIT"
srcDir = "src"
bin = @["ttop"]


# Dependencies

requires "nim >= 1.6.4"

requires "illwill"
requires "zippy"
requires "asciigraph"

task static, "build static release":
  exec "nim -d:release --stackTrace:on --lineTrace:on --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c src/ttop.nim"
