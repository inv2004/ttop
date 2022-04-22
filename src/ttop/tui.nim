import illwill
import os
import procfs
import strutils
import strformat
import tables
import times

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

const offset = 2

# proc header*(tb TerminalBuffer) =
proc header(tb: var TerminalBuffer) =

  let sys = sysInfo()

  tb.write(offset, 1, fgWhite, "RTC: ", $sys.datetime)
  tb.write(offset, 2, fgWhite)
  tb.write "CPU: ", sys.cpu.formatF().cut(4, false, 0), "  %|"
  for i, cpu in sys.cpus:
    if i == 0:
      tb.write " "
    tb.write cpu.formatF().cut(4, true, 0)
  tb.write "  |%"
  tb.write(offset, 3, "Press ", fgYellow, "ESC", fgWhite,
               " or ", fgYellow, "Q", fgWhite, " to quit")
  # tb.drawHorizLine(offset, tb.width - offset - 1, 3, doubleStyle=false)

proc table(tb: var TerminalBuffer, curSort: SortField, scrollX, scrollY: int) =
  var y = 4

  tb.write(offset, y, bgMagenta, fmt"""{"PID":>5} {"USER":<11} {"S":1} {"VIRT":>10} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"UP":>8}""", ' '.repeat(tb.width-66), bgNone)
  inc y

  for (i, p) in pidsInfo(curSort).pairs:
    if (y-4) < scrollY:
      continue
    tb.setCursorPos offset, y
    tb.write p.pid.cut(5, true, scrollX), " "
    if p.user == "":
      tb.write fgMagenta, int(p.uid).cut(10, false, scrollX), fgWhite, " "
    else:
      tb.write fgYellow, p.user.cut(10, false, scrollX), fgWhite, " "
    tb.write p.state, fgWhite, " "
    tb.write p.vsize.formatU().cut(10, true, scrollX), fgWhite, " "
    tb.write p.rss.formatU().cut(10, true, scrollX), fgWhite, " "
    tb.write p.mem.formatF().cut(5, true, scrollX), fgWhite, " "
    tb.write p.cpu.formatF().cut(5, true, scrollX), fgWhite, " "
    tb.write p.uptime.formatT().cut(8, false, scrollX)
    tb.write fgCyan, p.cmd.cut(tb.width - 68, false, scrollX), fgWhite

    inc y
    if y > tb.height-2:
      break

  while y <= tb.height-2:
    tb.setCursorPos offset, y
    tb.write ' '.repeat(tb.width-10)
    inc y


proc run*() =
  illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  hideCursor()
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)
  tb.setForegroundColor(fgBlack, true)
  tb.drawRect(0, 0, w-1, h-1)

  header(tb)

  var curSort = Rss
  var scrollX, scrollY = 0
  table(tb, curSort, scrollX, scrollY)

  var refresh = 0
  while true:
    var key = getKey()
    if key != Key.None:
      tb.write(60, 1, resetStyle, "Key pressed: ", fgGreen, $key)
    tb.write(30, 2, resetStyle)
    case key
    of Key.Escape, Key.Q: exitProc()
    of Key.Space: table(tb, curSort, scrollX, scrollY)
    of Key.Left:
      if scrollX > 0: dec scrollX
      table(tb, curSort, scrollX, scrollY)
    of Key.Right: inc scrollX; table(tb, curSort, scrollX, scrollY)
    of Key.Up:
      if scrollY > 0: dec scrollY
      table(tb, curSort, scrollX, scrollY)
    of Key.Down:
      inc scrollY
      table(tb, curSort, scrollX, scrollY)
    of Key.P: curSort = Pid; table(tb, curSort, scrollX, scrollY)
    of Key.M: curSort = Rss; table(tb, curSort, scrollX, scrollY)
    of Key.N: curSort = Name; table(tb, curSort, scrollX, scrollY)
    of Key.C: curSort = Cpu; table(tb, curSort, scrollX, scrollY)
    else: discard
  
    if refresh == 20:
      table(tb, curSort, scrollX, scrollY)
      refresh = 0
    else:
      inc refresh

    tb.display()
    sleep(100)
