# Package

version = "0.7.2"
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
requires "sensors >= 0.2.3"

const lmDir = "lm-sensors"

before static:
  if not dirExists(lmDir):
    exec "git clone https://github.com/lm-sensors/lm-sensors/ " & lmDir
    exec "cd " & lmDir & " && git checkout $(git tag | grep ^V3 | sort -V | tail -1)"
  if not fileExists(lmDir & "/lib/libsensors.a"):
    exec "cd " & lmDir & " && make CC=musl-gcc"

task static, "build static release":
  exec "nim -d:release -d:ssl -d:staticSensorsPath=" & lmDir & "/lib --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop c src/ttop.nim"

task staticdebug, "build static debug":
  exec "nim -d:debug -d:ssl -d:staticSensorsPath=" & lmDir & "/lib --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc --passL:-static -o:ttop-debug c src/ttop.nim"

