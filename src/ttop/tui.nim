import illwill
import os
import procfs
import strutils
import strformat
import tables
import times
import options
import limits
import format
import sequtils
import blog
import asciigraph
from terminal import setCursorXPos

proc stopTui() {.noconv.} =
  illwillDeinit()
  setCursorXPos(0)
  showCursor()

proc exitProc() {.noconv.} =
  stopTui()
  quit(0)

const offset = 2
const HelpCol = fgGreen

proc writeR(tb: var TerminalBuffer, s: string, rOffset = 0) =
  let x = terminalWidth() - s.len - offset - rOffset
  if tb.getCursorXPos < x:
    tb.setCursorXPos x
    tb.write(s)

proc chunks[T](x: openArray[T], n: int): seq[seq[T]] =
  var i = 0
  while i < x.len:
    result.add x[i..<min(i+n, x.len)]
    i += n

proc temp(tb: var TerminalBuffer, value: Option[float64], isLimit: bool) =
  if value.isSome:
    if isLimit:
      tb.write bgRed
    else:
      tb.write fgBlue, styleBright
    tb.writeR formatC(value.get), -1
    tb.write bgNone

proc header(tb: var TerminalBuffer, info: FullInfoRef, hist, cnt: int,
    blog: string) =
  let mi = info.mem
  tb.setCursorPos offset, 1
  tb.write bgCyan, info.sys.hostname, fgWhite, ": ",
      info.sys.datetime.format(
      "yyyy-MM-dd HH:mm:ss")
  if hist > 0:
    tb.write fmt"    {blog}: {hist} / {cnt} "
  elif blog == "":
    tb.write fmt"    autoupdate    log: empty "
  else:
    tb.write fmt"    autoupdate    {blog}: {cnt} "
  let curX = tb.getCursorXPos()
  if tb.width - curX - 2 > 0:
    tb.write ' '.repeat(tb.width - curX - 2)
  tb.setCursorXPos curX
  # let powerStr = fmt"{float(info.power) / 1000000:5.2f} W"
  let procStr = fmt"PROCS: {$info.pidsInfo.len}"
  tb.writeR procStr
  tb.setCursorPos(offset, 2)
  tb.write bgNone
  tb.write fgYellow, "CPU: ", fgNone
  if checkCpuLimit(info.cpu):
    tb.write bgRed
  tb.write styleBright, info.cpu.cpu.formatP(true), bgNone, "  %|"
  for i, cpu in info.cpus:
    if i > 0:
      tb.write "|"
    if checkCpuLimit(cpu):
      tb.write fgYellow, formatP(cpu.cpu), fgNone, styleBright
    else:
      tb.write formatP(cpu.cpu)
  tb.write "|%"
  temp(tb, info.temp.cpu, checkCpuTempLimit(info.temp))
  tb.setCursorPos(offset, 3)
  let memStr = formatD(mi.MemAvailable, mi.MemTotal)
  let sign = if mi.MemDiff > 0: '+' elif mi.MemDiff == 0: '=' else: '-'
  if checkMemLimit(mi):
    tb.write bgRed
  tb.write fgGreen, "MEM: ", fgNone, fgWhite, styleBright, memStr
  tb.write fmt"  {sign&abs(mi.MemDiff).formatS():>9}    BUF: {mi.Buffers.formatS()}    CACHE: {mi.Cached.formatS()}"
  if checkSwpLimit(mi):
    tb.write bgRed
  tb.write fmt"    SWP: {formatD(mi.SwapFree, mi.SwapTotal)}", bgNone

  let diskMatrix = chunks(info.disk.keys().toSeq(), 2)
  for i, diskRow in diskMatrix:
    tb.setCursorPos offset, 4+i
    if i == 0:
      tb.write fgCyan, "DSK: ", styleBright
    else:
      tb.write "     "
    for i, k in diskRow:
      if i > 0:
        tb.write " | "
      let disk = info.disk[k]
      let bg = if checkDiskLimit(disk): bgRed else: bgNone
      tb.write fgMagenta, disk.path, fgWhite, " ", bg,
          fmt"{formatD(disk.avail, disk.total)}", bgNone,
              fmt" (rw: {formatS(disk.ioUsageRead, disk.ioUsageWrite)})"
    if i == 0:
      temp(tb, info.temp.nvme, checkSsdTempLimit(info.temp))

  var netKeys = newSeq[string]()
  for k, v in info.net:
    if v.netIn == 0 and v.netOut == 0:
      continue
    netKeys.add k
  let netMatrix = chunks(netKeys, 4)
  var y = tb.getCursorYPos()+1
  for i, netRow in netMatrix:
    tb.setCursorPos offset, y+i
    if i == 0:
      tb.write fgMagenta, "NET: ", styleBright
    else:
      tb.write "     "
    for i, k in netRow:
      if i > 0:
        tb.write " | "
      let net = info.net[k]
      tb.write fgCyan, k, fgWhite, " ", formatS(net.netInDiff,
          net.netOutDiff)

proc graphData(stats: seq[StatV2], sort: SortField, width: int): seq[float] =
  case sort:
    of Cpu: result = stats.mapIt(it.cpu)
    of Mem: result = stats.mapIt(int(it.memTotal - it.memAvailable).formatSPair()[0])
    of Io: result = stats.mapIt(float(it.io))
    else: result = stats.mapIt(float(it.prc))

  if result.len < width:
    let diff = width - stats.len
    result.insert(float(0).repeat(diff), 0)

proc graph(tb: var TerminalBuffer, stats, live: seq[StatV2], blog: string, sort: SortField,
           hist: int, forceLive: bool) =
  tb.setCursorPos offset, tb.getCursorYPos()+1
  var y = tb.getCursorYPos() + 1
  tb.setCursorPos offset, y
  let w = terminalWidth()
  let graphWidth = w - 12
  let data =
    if forceLive or stats.len == 0: graphData(live, sort, graphWidth)
    else: graphData(stats, sort, 0)
  try:
    let gLines = plot(data, width = graphWidth, height = 4).split("\n")
    y += 5 - gLines.len
    for i, g in gLines:
      tb.setCursorPos offset-1, y+i
      tb.write g
    if hist > 0 and not forceLive:
      let cc = if data.len > 2: data.len - 1 else: 1
      let x = ((hist-1) * (w-11-2)) div (cc)
      tb.setCursorPos offset + 8 + x, tb.getCursorYPos() + 1
      tb.write styleBright, "^"
    else:
      tb.setCursorPos offset, tb.getCursorYPos() + 1
      if stats.len == 0 or forceLive:
        if stats.len == 0:
          tb.writeR("No historical stats found ", 5)
        tb.write bgGreen
        tb.writeR "LIVE"
        tb.write bgNone
      else:
        tb.writeR blog
  except:
    tb.write("error in graph: " & $deduplicate(data))
    tb.setCursorPos offset, tb.getCursorYPos() + 1

proc timeButtons(tb: var TerminalBuffer, cnt: int, forceLive: bool) =
  if cnt == 0:
    tb.write " ", styleDim, "[],{} - timeshift ", styleBright, fgNone
  else:
    tb.write " ", HelpCol, "[],{}", fgNone, " - timeshift "

proc help(tb: var TerminalBuffer, curSort: SortField, scrollX, scrollY,
    cnt: int, thr, forceLive: bool) =
  tb.setCursorPos offset, tb.height - 1

  tb.write fgNone, " order by"
  for x in SortField:
    if x == curSort:
      tb.write " ", styleBright, fgNone, $x
    else:
      tb.write " ", HelpCol, $($x)[0], fgCyan, ($x)[1..^1]
    # tb.setCursorXPos 0+tb.getCursorXPos()

  if thr:
    tb.write "  ", styleBright, fgNone, "T", fgNone, " - tree"
  else:
    tb.write "  ", HelpCol, "T", fgNone, " - tree"
  tb.write "  ", HelpCol, "/", fgNone, " - filter "
  timeButtons(tb, cnt, forceLive)
  if forceLive or cnt == 0:
    tb.write " ", styleBright, fgNone, "L", fgNone, " - live chart "
  else:
    tb.write " ", HelpCol, "L", fgNone, " - live chart "
  tb.write " ", HelpCol, "Esc,Q", fgNone, " - quit "

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
    filter: string, statsLen: int, thr: bool) =
  var y = tb.getCursorYPos() + 1
  tb.write styleBright
  tb.write(offset, y, bgBlue, fmt"""{"S":1} {"PID":>6} {"USER":<8} {"RSS":>10} {"MEM%":>5} {"CPU%":>5} {"r/w IO":>9} {"UP":>8}""")
  if thr:
    tb.write fmt""" {"THR":>3} """
  if tb.width - 63 > 0:
    tb.write ' '.repeat(tb.width-63), bgNone
  inc y
  var i: uint = 0
  tb.write fgWhite
  for (_, p) in pi.pairs:
    if filter.len >= 2:
      if filter[1..^1] notin $p.pid and filter[1..^1] notin toLowerAscii(p.cmd):
        continue
    if i < uint scrollY:
      inc i
      continue
    tb.setCursorPos offset, y
    tb.write p.state
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
    if thr:
      tb.write " ", ($p.threads).cut(3, true, scrollX)
    var cmd = ""
    if p.lvl > 0:
      cmd = repeat("·", p.lvl)
    if p.cmd != "":
      cmd.add p.cmd
    else:
      cmd.add p.name
    tb.write "  ", fgCyan, cmd.cut(tb.width - 65, false, scrollX), fgWhite

    inc y
    if y > tb.height-3:
      tb.setCursorPos (tb.width div 2)-1, tb.getCursorYPos()+1
      tb.write "..."
      break

proc filter(tb: var TerminalBuffer, filter: string, cnt: int, forceLive: bool) =
  tb.setCursorPos offset, tb.height - 1
  tb.write " ", HelpCol, "Esc,Ret", fgNone, " - Back "
  timeButtons(tb, cnt, forceLive)
  tb.write " Filter: ", bgBlue, filter[
      1..^1], bgNone

proc redraw(info: FullInfoRef, curSort: SortField, scrollX, scrollY: int,
            filter: string, hist: int, stats, live: seq[StatV2], blog: string,
                threads, forceLive: bool) =
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)

  if info == nil:
    tb.write fmt"blog not found {blog}: {hist} / {stats.len}"
    tb.display()
    return

  info.sort(curSort, threads)

  if checkAnyLimit(info):
    tb.setForegroundColor(fgRed, true)
    tb.drawRect(0, 0, w-1, h-1, true)
  # else:
    # tb.setForegroundColor(fgBlue, false)
    # tb.drawRect(0, 0, w-1, h-1, alarm)

  let blogShort = extractFilename blog
  header(tb, info, hist, stats.len, blogShort)
  graph(tb, stats, live, blogShort, curSort, hist, forceLive)
  table(tb, info.pidsInfo, curSort, scrollX, scrollY, filter, stats.len, threads)
  if filter.len > 0:
    filter(tb, filter, stats.len, forceLive)
  else:
    help(tb, curSort, scrollX, scrollY, stats.len, threads, forceLive)
  tb.display()

proc tui*() =
  init()
  illwillInit(fullscreen = true)
  defer: stopTui()
  setControlCHook(exitProc)
  hideCursor()
  var draw = false
  var (blog, hist) = moveBlog(0, "", 0, 0)
  var curSort = Cpu
  var scrollX, scrollY = 0
  var filter = ""
  var threads = false
  var forceLive = false
  var live = newSeq[StatV2]()
  var (info, stats) = hist(hist, blog, live)
  redraw(info, curSort, scrollX, scrollY, filter, hist, stats, live, blog,
      threads, forceLive)

  var refresh = 0
  while true:
    var key = getKey()
    if filter.len == 0:
      case key
      of Key.Escape, Key.Q: return
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
      of Key.T: threads = not threads; draw = true
      of Key.L: forceLive = not forceLive; draw = true
      of Key.Slash: filter = " "; draw = true
      of Key.LeftBracket:
        if not forceLive:
          (blog, hist) = moveBlog(-1, blog, hist, stats.len)
        else:
          forceLive = not forceLive
        draw = true
      of Key.RightBracket:
        if not forceLive:
          (blog, hist) = moveBlog(+1, blog, hist, stats.len)
        draw = true
      of Key.LeftBrace:
        if not forceLive:
          (blog, hist) = moveBlog(-1, blog, 1, stats.len)
        draw = true
      of Key.RightBrace:
        if not forceLive:
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
      of Key.Zero .. Key.Nine:
        filter.add char(key.int)
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
        if not forceLive:
          (blog, hist) = moveBlog(-1, blog, hist, stats.len)
        else:
          forceLive = not forceLive
        draw = true
      of Key.RightBracket:
        if not forceLive:
          (blog, hist) = moveBlog(+1, blog, hist, stats.len)
        draw = true
      of Key.LeftBrace:
        if not forceLive:
          (blog, hist) = moveBlog(-1, blog, 1, stats.len)
        draw = true
      of Key.RightBrace:
        if not forceLive:
          (blog, hist) = moveBlog(+1, blog, stats.len, stats.len)
        draw = true
      else: discard

    if draw or refresh == 10:
      if refresh == 10:
        if hist == 0:
          blog = moveBlog(+1, blog, stats.len, stats.len)[0]
        (info, stats) = hist(hist, blog, live)
        refresh = 0
      redraw(info, curSort, scrollX, scrollY, filter, hist, stats, live, blog,
          threads, forceLive)
      if draw:
        draw = false
      else:
        sleep 100
    else:
      inc refresh
      sleep 100

