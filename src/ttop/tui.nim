import illwill
import os
import procfs
import strutils
import strformat
import tables
import times
import limits
import format
import sequtils

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

const offset = 2

proc writeR(tb: var TerminalBuffer, s: string) =
  let x = terminalWidth() - s.len - offset
  if tb.getCursorXPos < x:
    tb.setCursorXPos x
    tb.write(s)

proc header(tb: var TerminalBuffer, info: FullInfo) =
  let mi = info.mem
  tb.write(offset, 1, fgWhite)
  tb.write fgBlue, info.sys.hostname, fgWhite, ": ", info.sys.datetime.format(
      "yyyy-MM-dd HH:mm:ss")
  tb.setCursorXPos 70
  tb.writeR fmt"PROCS: {$info.pidsInfo.len} "
  tb.setCursorPos(offset, 2)
  if info.cpu.cpu > cpuLimit:
    tb.write bgRed
  tb.write styleDim, "CPU: ", styleBright, info.cpu.cpu.formatP(true), bgNone, "  %|"
  tb.write info.cpus.mapIt(it.cpu.formatP).join("|")
  tb.write "|%"
  tb.setCursorPos(offset, 3)
  let memStr = formatS(mi.MemTotal - mi.MemFree, mi.MemTotal)
  let sign = if mi.MemDiff > 0: '+' elif mi.MemDiff == 0: '=' else: '-'
  let memChk = 100 * float(mi.MemTotal - mi.MemFree) / float(mi.MemTotal)
  if memChk >= memLimit:
    tb.write bgRed
  tb.write styleDim, "MEM: ", styleBright, memStr, bgNone
  tb.write fmt"  {sign&abs(mi.MemDiff).formatS():>9}    BUF: {mi.Buffers.formatS()}    CACHE: {mi.Cached.formatS()}"
  let swpChk = 100 * float(mi.SwapTotal - mi.SwapFree) / float(mi.SwapTotal)
  if swpChk >= swpLimit:
    tb.write bgRed
  tb.write fmt"    SWP: {formatS(mi.SwapTotal - mi.SwapFree, mi.SwapTotal)}", bgNone
  var i = 0
  for _, disk in info.disk:
    if i mod 2 == 0:
      tb.setCursorPos offset, 4+(i div 2)
      if i == 0:
        tb.write styleDim, "DSK: ", styleBright
      else:
        tb.write "  "
    if i > 0:
      tb.write " | "
    tb.write fgBlue, disk.path, fgWhite, fmt" {formatS(disk.total - disk.avail, disk.total)} (rw: {formatS(disk.ioUsageRead, disk.ioUsageWrite)})"
    inc i
  tb.setCursorPos(offset, tb.getCursorYPos + 1)
  tb.write styleDim, "NET: ", styleBright
  i = 0
  for name, net in info.net:
    if net.netIn == 0 or net.netOut == 0:
      continue
    if i > 0:
      tb.write " | "
    tb.write fgMagenta, name, fgWhite, " ", formatS(net.netInDiff,
        net.netOutDiff)
    inc i

proc help(tb: var TerminalBuffer, curSort: SortField, scrollX, scrollY: int) =
  tb.setCursorPos offset, tb.height - 1

  for x in SortField:
    if x == curSort:
      tb.write fgCyan, " ", $($x)[0], " - by ", $x, " ", fgNone
    else:
      tb.write " ", fgMagenta, $($x)[0], fgNone, " - by ", $x, " "
    tb.setCursorXPos 0+tb.getCursorXPos()

  tb.write " ", fgMagenta, "/", fgNone, " - filter "
  tb.write " ", fgMagenta, "Q", fgNone, " - quit "

  tb.setForegroundColor(fgBlack, true)
  let x = tb.getCursorXPos()

  let (w, h) = terminalSize()
  if x + 26 < w:
    if scrollX > 0:
      tb.setCursorXPos(w - 26)
      tb.write fmt" X: {scrollX}"
    if scrollY > 0:
      tb.setCursorXPos(w - 21)
      tb.write fmt" Y: {scrollY}"

  if x + 15 < w:
    tb.setCursorXPos(w - 15)
    tb.write fmt " W: {w} H: {h} "

proc table(tb: var TerminalBuffer, pi: OrderedTable[uint, PidInfo],
    curSort: SortField, scrollX, scrollY: int,
    filter: string) =
  var y = 7
  tb.write(offset, y, bgBlue, fmt"""{"S":1} {"PID":>6} {"USER":<9} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"r/w IO":>15} {"UP":>8}""",
      ' '.repeat(tb.width-72), bgNone)
  inc y
  var i: uint = 0
  for (_, p) in pi.pairs:
    if filter.len >= 2 and filter[1..^1] notin toLowerAscii(p.cmd):
      continue
    if i < uint scrollY:
      inc i
      continue
    tb.setCursorPos offset, y
    tb.write p.state, fgWhite, " "
    tb.write p.pid.cut(6, true, scrollX), " "
    if p.user == "":
      tb.write fgMagenta, int(p.uid).cut(8, false, scrollX), fgWhite, " "
    else:
      tb.write fgYellow, p.user.cut(8, false, scrollX), fgWhite, " "
    # tb.write p.vsize.formatU().cut(10, true, scrollX), fgWhite, " "
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write p.rss.formatU().cut(10, true, scrollX), bgNone, " "
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write p.mem.formatF().cut(5, true, scrollX), bgNone, " "
    if p.cpu >= cpuLimit:
      tb.write bgRed
    tb.write p.cpu.formatF().cut(5, true, scrollX), bgNone, " "
    var rwStr = ""
    if p.ioReadDiff + p.ioWriteDiff > 0:
      rwStr = fmt"{formatS(p.ioReadDiff, p.ioWriteDiff)}"
    tb.write rwStr.cut(15, true, scrollX), " "

    tb.write p.uptime.formatT().cut(8, false, scrollX)
    let cmd = if p.cmd != "": p.cmd else: p.name
    tb.write fgCyan, cmd.cut(tb.width - 72, false, scrollX), fgWhite

    inc y
    if y > tb.height-2:
      break

  while y <= tb.height-2:
    tb.setCursorPos offset, y
    tb.write ' '.repeat(tb.width-10)
    inc y

proc filter(tb: var TerminalBuffer, filter: string) =
  tb.setCursorPos offset, tb.height - 1
  tb.write " ", fgMagenta, "Esc", fgNone, " - Back    Filter: ", bgBlue, filter[
      1..^1], bgNone

proc redraw(curSort: SortField, scrollX, scrollY: int, filter: string) =
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)

  let info = fullInfo(curSort)

  if info.cpu.cpu >= cpuCoreLimit:
    tb.setForegroundColor(fgRed, true)
  else:
    tb.setForegroundColor(fgBlack, true)
  tb.drawRect(0, 0, w-1, h-1)

  header(tb, info)
  table(tb, info.pidsInfo, curSort, scrollX, scrollY, filter)
  if filter.len > 0:
    filter(tb, filter)
  else:
    help(tb, curSort, scrollX, scrollY)
  tb.display()

proc run*() =
  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()
  var draw = false
  var curSort = Cpu
  var scrollX, scrollY = 0
  var filter = ""
  redraw(curSort, scrollX, scrollY, filter)

  var refresh = 0
  while true:
    var key = getKey()
    if filter.len == 0:
      case key
      of Key.Escape, Key.Q: exitProc()
      of Key.Space: draw = true
      of Key.Left:
        if scrollX > 0: dec scrollX
        draw = true
      of Key.Right:
        inc scrollX;
        draw = true
      of Key.Up:
        if scrollY > 0: dec scrollY
        draw = true
      of Key.PageUp:
        if scrollY > 0: scrollY -= 10
        if scrollY < 0: scrollY = 0
        draw = true
      of Key.Down: inc scrollY; draw = true
      of Key.PageDown:
        scrollY += 10
        draw = true
      of Key.P: curSort = Pid; draw = true
      of Key.M: curSort = Mem; draw = true
      of Key.I: curSort = Io; draw = true
      of Key.N: curSort = Name; draw = true
      of Key.C: curSort = Cpu; draw = true
      of Key.Slash: filter = " "; draw = true
      else: discard
    else:
      case key
      of Key.Escape:
        filter = ""
        draw = true
      of Key.A .. Key.Z:
        filter.add toLowerAscii($key)
        draw = true
      of Key.Backspace:
        if filter.len >= 2:
          filter = filter[0..^2]
          draw = true
      of Key.Left:
        if scrollX > 0: dec scrollX
        draw = true
      of Key.Right:
        inc scrollX;
        draw = true
      else: discard

    if draw or refresh == 10:
      redraw(curSort, scrollX, scrollY, filter)
      refresh = 0
      if not draw:
        sleep 100
      draw = false
    else:
      inc refresh
      sleep 100

