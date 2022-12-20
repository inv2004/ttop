# Package

version = "0.1.0"
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

