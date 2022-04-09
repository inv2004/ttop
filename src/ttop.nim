# This is just an example to get you started. A typical binary package
# uses this
import ttop/procfs
import ttop/tui
import terminaltables
import strutils

# proc ps(): string =
#   let tbl = newUnicodeTable()
#   tbl.separateRows = false
#   tbl.setHeaders(@["pid", "user", "name", "state", "vsize", "rss", "cpu", "mem", "cmd"])
#   for p in pidsInfo():
#     tbl.addRow p.row()
#   tbl.render()

# proc writeM(str: string, tb: var TerminalBuffer, x, y: int) =
#   var yy = y
#   for line in str.splitLines(false):
#     tb.write(x, yy, line)
#     yy.inc()

proc main() =
  run()

when isMainModule:
  main()
