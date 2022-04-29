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
proc header(tb: var TerminalBuffer, info: FullInfo) =
  let si = info.sys
  let mi = info.mem
  tb.write(offset, 1, fgWhite)
  tb.write "RTC: ", si.datetime.format("yyyy-MM-dd  HH:mm:ss"), "  PROCS: ", $info.pidsInfo.len
  tb.setCursorPos(offset, 2)
  tb.write "CPU: ", si.cpu.cpu.formatF().cut(4, false, 0), "%|"
  for i, cpu in si.cpus:
    if i > 0:
      tb.write "|"
    if cpu.cpu >= 10:
      tb.write fgRed
    tb.write cpu.cpu.formatF().cut(4, true, 0)
    if cpu.cpu >= 10:
      tb.write fgNone
  tb.write " |%"
  tb.setCursorPos(offset, 3)
  let memStr = fmt"{formatUU(mi.MemTotal - mi.MemFree)} / {mi.MemTotal.formatU()}".cut(20, false, 0)
  let sign = if mi.MemDiff > 0: '+' elif mi.MemDiff == 0: '=' else: '-'
  tb.write fmt"MEM: {memStr} DIFF: {sign}{uint(abs(mi.MemDiff)).formatU().cut(10, false, 0)} BUF: {mi.Buffers.formatU().cut(10, false, 0)} CACHE: {mi.Cached.formatU().cut(10, false, 0)}"

proc help(tb: var TerminalBuffer, curSort: SortField, scrollY: int) =
  tb.setCursorPos offset, tb.height - 1

  for x in SortField:
    let str = fmt" {($x)[0]} - by {x} "
    if x == curSort:
      tb.write(fgCyan, str, fgNone)
    else:
      tb.write(str)
    tb.setCursorXPos 3+tb.getCursorXPos()

  if scrollY > 0:
    tb.write fmt" Y: {scrollY} "
  else:
    tb.write "-".repeat(20)

proc table(tb: var TerminalBuffer, pi: OrderedTable[uint, PidInfo], curSort: SortField, scrollX, scrollY: int) =
  var y = 5
  tb.write(offset, y, bgBlue, fmt"""{"PID":>5} {"USER":<11} {"S":1} {"VIRT":>10} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"UP":>8}""", ' '.repeat(tb.width-66), bgNone)
  inc y
  for (i, p) in pi.pairs:
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
    if p.mem >= 10:
      tb.write fgRed
    tb.write p.rss.formatU().cut(10, true, scrollX), fgWhite, " "
    if p.mem >= 10:
      tb.write fgRed
    tb.write p.mem.formatF().cut(5, true, scrollX), fgWhite, " "
    if p.cpu >= 20:
      tb.write fgRed
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

proc redraw(tb: var TerminalBuffer, curSort: SortField, scrollX, scrollY: int) =
  let info = fullInfo(curSort)
  header(tb, info)
  table(tb, info.pidsInfo, curSort, scrollX, scrollY)
  help(tb, curSort, scrollY)

proc run*() =
  illwillInit(fullscreen=true)
  setControlCHook(exitProc)
  hideCursor()
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)
  tb.setForegroundColor(fgBlack, true)
  tb.drawRect(0, 0, w-1, h-1)

  var curSort = Cpu
  var scrollX, scrollY = 0
  redraw(tb, curSort, scrollX, scrollY)

  var refresh = 0
  while true:
    var key = getKey()
    if key != Key.None:
      tb.write(60, 1, resetStyle, "Key pressed: ", fgGreen, $key, "    ")
    tb.write(30, 2, resetStyle)
    case key
    of Key.Escape, Key.Q: exitProc()
    of Key.Space: redraw(tb, curSort, scrollX, scrollY)
    of Key.Left:
      if scrollX > 0: dec scrollX
      redraw(tb, curSort, scrollX, scrollY)
    of Key.Right: inc scrollX; redraw(tb, curSort, scrollX, scrollY)
    of Key.Up:
      if scrollY > 0: dec scrollY
      redraw(tb, curSort, scrollX, scrollY)
    of Key.Down: inc scrollY; redraw(tb, curSort, scrollX, scrollY)
    of Key.P: curSort = Pid; redraw(tb, curSort, scrollX, scrollY)
    of Key.R: curSort = Rss; redraw(tb, curSort, scrollX, scrollY)
    of Key.N: curSort = Name; redraw(tb, curSort, scrollX, scrollY)
    of Key.C: curSort = Cpu; redraw(tb, curSort, scrollX, scrollY)
    else: discard
  
    if refresh == 20:
      redraw(tb, curSort, scrollX, scrollY)
      refresh = 0
    else:
      inc refresh

    tb.display()
    sleep(100)
