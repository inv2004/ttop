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
import blog
import asciigraph

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

const offset = 2
const HelpCol = fgGreen

proc writeR(tb: var TerminalBuffer, s: string) =
  let x = terminalWidth() - s.len - offset
  if tb.getCursorXPos < x:
    tb.setCursorXPos x
    tb.write(s)

proc header(tb: var TerminalBuffer, info: FullInfoRef, hist, cnt: int,
    blog: string) =
  let mi = info.mem
  tb.write(offset, 1, fgWhite)
  tb.write fgBlue, info.sys.hostname, fgWhite, ": ", info.sys.datetime.format(
      "yyyy-MM-dd HH:mm:ss")
  let blogShort = extractFilename blog
  if hist > 0:
    tb.write fmt"    {blogShort}: {hist} / {cnt}"
  elif blog == "":
    tb.write fmt"    autoupdate    log: empty"
  else:
    tb.write fmt"    autoupdate    {blogShort}: {cnt}"
  tb.writeR fmt"PROCS: {$info.pidsInfo.len} "
  tb.setCursorPos(offset, 2)
  tb.write styleDim, "CPU: ", styleBright
  if info.cpu.cpu > cpuLimit:
    tb.write bgRed
  tb.write info.cpu.cpu.formatP(true), bgNone, "  %|"
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

proc graphData(stats: seq[StatV1], sort: SortField): seq[float] =
  case sort:
    of Cpu: return stats.mapIt(it.cpu)
    of Mem: return stats.mapIt(int(it.mem).formatSPair()[0])
    of Io: return stats.mapIt(float(it.io))
    else: return stats.mapIt(float(it.prc))

proc graph(tb: var TerminalBuffer, stats: seq[StatV1], sort: SortField, hist, cnt: int) =
  if stats.len == 0:
    return
  var y = tb.getCursorYPos() + 2
  tb.setCursorPos offset, y
  let data = graphData(stats, sort)
  let w = terminalWidth()
  let gLines = plot(data, width = w - 11, height = 4).split("\n")
  # height = 5 or 8
  y += 5 - gLines.len
  for i, g in gLines:
    tb.setCursorPos offset-1, y+i
    tb.write g
  if hist > 0:
    let cc = if cnt > 2: cnt - 1 else: 1
    let x = ((hist-1) * (w-11-2)) div (cc)
    tb.setCursorPos offset + 8 + x, tb.getCursorYPos() + 1
    tb.write "^"
  else:
    tb.setCursorPos offset, tb.getCursorYPos() + 1

proc timeButtons(tb: var TerminalBuffer, cnt: int) =
  if cnt > 0:
    tb.write " ", HelpCol, "[],{}", fgNone, " - timeshift "
  else:
    tb.write " ", styleDim, "[],{} - timeshift ", styleBright, fgNone

proc help(tb: var TerminalBuffer, curSort: SortField, scrollX, scrollY, cnt: int) =
  tb.setCursorPos offset, tb.height - 1

  for x in SortField:
    if x == curSort:
      tb.write fgCyan, " ", $($x)[0], " - by ", $x, " ", fgNone
    else:
      tb.write " ", HelpCol, $($x)[0], fgNone, " - by ", $x, " "
    # tb.setCursorXPos 0+tb.getCursorXPos()

  tb.write " ", HelpCol, "/", fgNone, " - filter "
  timeButtons(tb, cnt)
  tb.write " ", HelpCol, "Esc,Q", fgNone, " - quit "

  # tb.setForegroundColor(fgBlack, true)
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
    tb.write fmt " WH: {w}x{h} "

proc table(tb: var TerminalBuffer, pi: OrderedTableRef[uint, PidInfo],
    curSort: SortField, scrollX, scrollY: int,
    filter: string, statsLen: int) =
  var y = tb.getCursorYPos() + 1
  tb.write(offset, y, bgBlue, fmt"""{"S":1} {"PID":>6} {"USER":<8} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"r/w IO":>9} {"UP":>8}""",
      ' '.repeat(tb.width-63), bgNone)
  inc y
  var i: uint = 0
  for (_, p) in pi.pairs:
    if filter.len >= 2 and filter[1..^1] notin toLowerAscii(p.cmd):
      continue
    if i < uint scrollY:
      inc i
      continue
    tb.setCursorPos offset, y
    tb.write p.state, fgWhite
    tb.write " ", p.pid.cut(6, true, scrollX)
    if p.user == "":
      tb.write " ", fgMagenta, int(p.uid).cut(8, false, scrollX), fgWhite
    else:
      tb.write " ", fgYellow, p.user.cut(8, false, scrollX), fgWhite
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write " ", p.rss.formatS().cut(10, true, scrollX), bgNone
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write " ", p.mem.formatP().cut(5, true, scrollX), bgNone
    if p.cpu >= cpuLimit:
      tb.write bgRed
    tb.write " ", p.cpu.formatP().cut(5, true, scrollX), bgNone
    var rwStr = ""
    if p.ioReadDiff + p.ioWriteDiff > 0:
      rwStr = fmt"{formatSI(p.ioReadDiff, p.ioWriteDiff)}"
    tb.write " ", rwStr.cut(9, true, scrollX)

    tb.write " ", p.uptime.formatT().cut(8, false, scrollX)
    let cmd = if p.cmd != "": p.cmd else: p.name
    tb.write "  ", fgCyan, cmd.cut(tb.width - 65, false, scrollX), fgWhite

    inc y
    if y > tb.height-2:
      break

  while y <= tb.height-2:
    tb.setCursorPos offset, y
    tb.write ' '.repeat(tb.width-10)
    inc y

proc filter(tb: var TerminalBuffer, filter: string, cnt: int) =
  tb.setCursorPos offset, tb.height - 1
  tb.write " ", HelpCol, "Esc,Ret", fgNone, " - Back "
  timeButtons(tb, cnt)
  tb.write " Filter: ", bgBlue, filter[
      1..^1], bgNone

proc redraw(info: FullInfoRef, curSort: SortField, scrollX, scrollY: int,
            filter: string, hist: int, stats: seq[StatV1], blog: string) =
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)

  if info == nil:
    tb.write fmt"blog not found {blog}: {hist} / {stats.len}"
    tb.display()
    return

  info.sort(curSort)

  let alarm = info.cpu.cpu >= cpuCoreLimit
  if alarm:
    tb.setForegroundColor(fgRed, true)
  else:
    tb.setForegroundColor(fgWhite, false)
  tb.drawRect(0, 0, w-1, h-1, alarm)

  header(tb, info, hist, stats.len, blog)
  graph(tb, stats, curSort, hist, stats.len)
  table(tb, info.pidsInfo, curSort, scrollX, scrollY, filter, stats.len)
  if filter.len > 0:
    filter(tb, filter, stats.len)
  else:
    help(tb, curSort, scrollX, scrollY, stats.len)
  tb.display()

proc run*() =
  init()
  illwillInit(fullscreen = true)
  setControlCHook(exitProc)
  hideCursor()
  var draw = false
  var (blog, hist) = moveBlog(0, "", 0, 0)
  var curSort = Cpu
  var scrollX, scrollY = 0
  var filter = ""
  var (info, stats) = hist(hist, blog)
  redraw(info, curSort, scrollX, scrollY, filter, hist, stats, blog)

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
      of Key.LeftBracket:
        (blog, hist) = moveBlog(-1, blog, hist, stats.len)
        draw = true
      of Key.RightBracket:
        (blog, hist) = moveBlog(+1, blog, hist, stats.len)
        draw = true
      of Key.LeftBrace:
        (blog, hist) = moveBlog(-1, blog, 1, stats.len)
        draw = true
      of Key.RightBrace:
        (blog, hist) = moveBlog(+1, blog, stats.len, stats.len)
        draw = true
      else: discard
    else:
      case key
      of Key.Escape, Key.Enter:
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
      of Key.LeftBracket:
        (blog, hist) = moveBlog(-1, blog, hist, stats.len)
        draw = true
      of Key.RightBracket:
        (blog, hist) = moveBlog(+1, blog, hist, stats.len)
        draw = true
      of Key.LeftBrace:
        (blog, hist) = moveBlog(-1, blog, 1, stats.len)
        draw = true
      of Key.RightBrace:
        (blog, hist) = moveBlog(+1, blog, stats.len, stats.len)
        draw = true
      else: discard

    if draw or refresh == 10:
      if hist == 0:
        blog = moveBlog(+1, blog, stats.len, stats.len)[0]
      (info, stats) = hist(hist, blog)
      redraw(info, curSort, scrollX, scrollY, filter, hist, stats, blog)
      refresh = 0
      if draw:
        draw = false
      else:
        sleep 100
    else:
      inc refresh
      sleep 100

