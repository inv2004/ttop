import illwill
import os
import procfs
import strutils
import strformat
import tables
import times
import limits

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

const offset = 2

proc header(tb: var TerminalBuffer, info: FullInfo) =
  let si = info.sys
  let mi = info.mem
  tb.write(offset, 1, fgWhite)
  tb.write "RTC: ", si.datetime.format("yyyy-MM-dd  HH:mm:ss"),
      "                                      PROCS: ", $info.pidsInfo.len
  tb.setCursorPos(offset, 2)
  tb.write "CPU: ", si.cpu.cpu.formatF().cut(4, false, 0), "%|"
  for i, cpu in si.cpus:
    if i > 0:
      tb.write "|"
    if cpu.cpu >= cpuCoreLimit:
      tb.write fgRed
    tb.write cpu.cpu.formatF().cut(4, true, 0), fgNone
  tb.write " |%"
  tb.setCursorPos(offset, 3)
  let memStr = fmt"{formatUU(mi.MemTotal - mi.MemFree)} / {mi.MemTotal.formatU()}"
  let sign = if mi.MemDiff > 0: '+' elif mi.MemDiff == 0: '=' else: '-'
  let memChk = 100 * float(mi.MemTotal - mi.MemFree) / float(mi.MemTotal)
  if memChk >= memLimit:
    tb.write fgRed
  tb.write fmt"MEM: {memStr:16}   ", fgWhite
  tb.write fmt"DIFF: {sign}{uint(abs(mi.MemDiff)).formatU():10} BUF: {mi.Buffers.formatU():10} CACHE: {mi.Cached.formatU():10}  ", fgWhite
  let swpStr = fmt"{formatUU(mi.SwapTotal - mi.SwapFree)} / {mi.SwapTotal.formatU()}"
  let swpChk = 100 * float(mi.SwapTotal - mi.SwapFree) / float(mi.SwapTotal)
  if swpChk >= swpLimit:
    tb.write fgRed
  tb.write fmt"SWP: {swpStr:16}"
  tb.setCursorPos(offset, 4)
  tb.write fmt"DSK: "
  var i = 0
  for name, disk in info.disk:
    let used = disk.total - disk.avail
    if i > 0:
      tb.write " | "
    tb.write fmt"{name} {used.formatUU()} / {disk.total.formatU()} (rw: {disk.ioUsageRead.formatF()}/{disk.ioUsageWrite.formatF()}%)"
    inc i

proc help(tb: var TerminalBuffer, curSort: SortField, scrollY: int) =
  tb.setCursorPos offset, tb.height - 1

  for x in SortField:
    let str = fmt" {($x)[0]} - by {x} "
    if x == curSort:
      tb.write(fgCyan, str, fgNone)
    else:
      tb.write(str)
    tb.setCursorXPos 0+tb.getCursorXPos()

  tb.write fmt" Q - quit "

  if scrollY > 0:
    tb.write fmt" Y: {scrollY} "
  else:
    tb.setForegroundColor(fgBlack, true)
    let (x, y) = tb.getCursorPos()
    tb.drawHorizLine(x, x+10, y)

proc table(tb: var TerminalBuffer, pi: OrderedTable[uint, PidInfo],
    curSort: SortField, scrollX, scrollY: int) =
  var y = 6
  tb.write(offset, y, bgBlue, fmt"""{"S":1} {"PID":>6} {"USER":<9} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"r/w IO":>15} {"r/t NET":>15} {"UP":>8}""",
      ' '.repeat(tb.width-72), bgNone)
  inc y
  var i: uint = 0
  for (_, p) in pi.pairs:
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
      tb.write fgRed
    tb.write p.rss.formatU().cut(10, true, scrollX), fgWhite, " "
    if p.mem >= rssLimit:
      tb.write fgRed
    tb.write p.mem.formatF().cut(5, true, scrollX), fgWhite, " "
    if p.cpu >= cpuLimit:
      tb.write fgRed
    tb.write p.cpu.formatF().cut(5, true, scrollX), fgWhite, " "
    var rwStr = ""
    if p.ioReadDiff + p.ioWriteDiff > 0:
      rwStr = fmt"{p.ioReadDiff.formatUU()}/{p.ioWriteDiff.formatU()}"
    tb.write rwStr.cut(15, true, scrollX), " "
    rwStr = ""
    if p.netInDiff + p.netOutDiff > 0:
      rwStr = fmt"{p.netInDiff.formatUU()}/{p.netOutDiff.formatU()}"
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

proc redraw(curSort: SortField, scrollX, scrollY: int) =
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)
  tb.setForegroundColor(fgBlack, true)
  tb.drawRect(0, 0, w-1, h-1)

  let info = fullInfo(curSort)
  header(tb, info)
  table(tb, info.pidsInfo, curSort, scrollX, scrollY)
  help(tb, curSort, scrollY)
  tb.display()

proc run*() =
  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()
  var curSort = Cpu
  var scrollX, scrollY = 0
  redraw(curSort, scrollX, scrollY)

  var refresh = 0
  while true:
    var key = getKey()
    # if key != Key.None:
    #   tb.write(80, 1, resetStyle, "Key pressed: ", fgGreen, $key, "    ")
    #   tb.write(80, 2, resetStyle, "W: ", fgGreen, $tb.width)
    # tb.write(30, 2, resetStyle)
    case key
    of Key.Escape, Key.Q: exitProc()
    of Key.Space: redraw(curSort, scrollX, scrollY)
    of Key.Left:
      if scrollX > 0: dec scrollX
      redraw(curSort, scrollX, scrollY)
    of Key.Right: inc scrollX; redraw(curSort, scrollX, scrollY)
    of Key.Up:
      if scrollY > 0: dec scrollY
      redraw(curSort, scrollX, scrollY)
    of Key.Down: inc scrollY; redraw(curSort, scrollX, scrollY)
    of Key.P: curSort = Pid; redraw(curSort, scrollX, scrollY)
    of Key.M: curSort = Mem; redraw(curSort, scrollX, scrollY)
    of Key.I: curSort = Io; redraw(curSort, scrollX, scrollY)
    of Key.N: curSort = Name; redraw(curSort, scrollX, scrollY)
    of Key.C: curSort = Cpu; redraw(curSort, scrollX, scrollY)
    else: discard

    if refresh == 10:
      redraw(curSort, scrollX, scrollY)
      refresh = 0
    else:
      inc refresh

    sleep(100)
