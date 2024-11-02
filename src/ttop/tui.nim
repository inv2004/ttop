import illwill
import os
import procfs
import config
import strutils
import strformat
import tables
import times
import std/monotimes
import options
import limits
import format
import sequtils
import blog
import asciigraph
from terminal import setCursorXPos

const fgDarkColor = fgWhite
const fgLightColor = fgBlack
var fgColor = fgDarkColor

const offset = 2
const HelpCol = fgGreen

type
  Tui = ref object
    sort: SortField
    scrollX: int
    scrollY: int
    filter: Option[string]
    threads: bool
    group: bool
    kernel: bool
    forceLive: bool
    draw: bool
    reload: bool
    quit: bool
    hist: int
    blog: string
    refresh: bool

proc stopTui() {.noconv.} =
  illwillDeinit()
  setCursorXPos(0)
  showCursor()

proc exitProc() {.noconv.} =
  stopTui()
  quit(0)

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

proc header(tui: Tui, tb: var TerminalBuffer, info: FullInfoRef, cnt: int,
    blog: string) =
  let mi = info.mem
  tb.setCursorPos offset, 1
  tb.write info.sys.hostname, "    ",
      info.sys.datetime.format(
      "yyyy-MM-dd HH:mm:ss")
  tb.write styleDim
  if tui.hist > 0:
    tb.write fmt"                  {blog} {tui.hist}/{cnt} "
  elif blog == "":
    tb.write fmt"    autoupdate    log: empty "
  else:
    tb.write fmt"    autoupdate    {blog} {cnt}/{cnt} "
  let curX = tb.getCursorXPos()
  if tb.width - curX - 2 > 0:
    tb.write ' '.repeat(tb.width - curX - 2)
  tb.setCursorXPos curX
  tb.write resetStyle
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
  tb.write fgGreen, "MEM: ", fgNone, fgColor, styleBright, memStr
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
      tb.write fgMagenta, disk.path, fgColor, " ", bg,
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
      tb.write fgCyan, k, fgColor, " ", formatS(net.netInDiff,
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

proc graph(tui: Tui, tb: var TerminalBuffer, stats, live: seq[StatV2],
    blog: string) =
  tb.setCursorPos offset, tb.getCursorYPos()+1
  var y = tb.getCursorYPos() + 1
  tb.setCursorPos offset, y
  let w = terminalWidth()
  let graphWidth = w - 12
  let data =
    if tui.forceLive or stats.len == 0: graphData(live, tui.sort, graphWidth)
    else: graphData(stats, tui.sort, 0)
  try:
    let gLines = plot(data, width = graphWidth, height = 4).split("\n")
    y += 5 - gLines.len
    for i, g in gLines:
      tb.setCursorPos offset-1, y+i
      tb.write g
    if tui.hist > 0 and not tui.forceLive:
      let cc = if data.len > 2: data.len - 1 else: 1
      let x = ((tui.hist-1) * (w-11-2)) div (cc)
      tb.setCursorPos offset + 8 + x, tb.getCursorYPos() + 1
      tb.write styleBright, "^"
    else:
      tb.setCursorPos offset, tb.getCursorYPos() + 1
      if stats.len == 0 or tui.forceLive:
        if stats.len == 0:
          tb.writeR("No historical stats found ", 5)
        tb.write bgGreen
        tb.writeR "LIVE"
        tb.write bgNone
      else:
        tb.writeR blog
  except CatchableError, Defect:
    tb.write("error in graph: " & $deduplicate(data))
    tb.setCursorPos offset, tb.getCursorYPos() + 1

proc timeButtons(tb: var TerminalBuffer, cnt: int) =
  if cnt == 0:
    tb.write " ", styleDim, "[]", fgNone, ",", HelpCol, "{} - timeshift ",
        styleBright, fgNone
  else:
    tb.write " ", HelpCol, "[]", fgNone, ",", HelpCol, "{}", fgNone, " - timeshift "

proc help(tui: Tui, tb: var TerminalBuffer, w, h, cnt: int) =
  tb.setCursorPos offset - 1, tb.height - 1

  tb.write fgNone
  for x in SortField:
    if x == tui.sort:
      tb.write " ", styleBright, fgNone, $x
    else:
      tb.write " ", HelpCol, $($x)[0], fgCyan, ($x)[1..^1]

  if tui.group:
    tb.write "  ", styleBright, fgNone
  else:
    tb.write "  ", HelpCol
  tb.write "G", fgNone, " - group"
  if tui.threads:
    tb.write "  ", styleBright, fgNone
  else:
    tb.write "  ", HelpCol
  tb.write "T", fgNone, " - tree"
  tb.write "  ", HelpCol, "/", fgNone, " - filter "
  timeButtons(tb, cnt)
  if tui.forceLive or cnt == 0:
    tb.write " ", styleBright, fgNone, "L", fgNone, " - live "
  else:
    tb.write " ", HelpCol, "L", fgNone, " - live "
  tb.write " ", HelpCol, "Esc,Q", fgNone, " - quit "

  let x = tb.getCursorXPos()

  if x + 26 < w:
    if tui.scrollX > 0:
      tb.setCursorXPos(w - 26)
      tb.write fmt" X: {tui.scrollX}"
    if tui.scrollY > 0:
      tb.setCursorXPos(w - 21)
      tb.write fmt" Y: {tui.scrollY}"

  if x + 15 < w:
    tb.setCursorXPos(w - 15)
    if tui.scrollX > 0 or tui.scrollY > 0:
      tb.write HelpCol, " ", fgNone
    else:
      tb.write " "
    tb.write fmt "WH: {w}x{h} "

proc checkFilter(filter: string, p: PidInfo): bool =
  for fWord in filter.split():
    if fWord == "@":
      if p.user == "root":
        result = true
    elif fWord.startsWith("@"):
      if p.user == "":
        if fWord[1..^1] notin ($p.uid):
          result = true
      elif fWord[1..^1] notin p.user:
        result = true
    elif fWord == "#":
      if p.docker == "":
        result = true
    elif fWord.startsWith("#"):
      if fWord[1..^1] notin p.docker:
        result = true
    elif fWord notin $p.pid and
          fWord notin toLowerAscii(p.cmd) and
          fWord notin toLowerAscii(p.name) and
          fWord notin toLowerAscii(p.docker):
      result = true

proc table(tui: Tui, tb: var TerminalBuffer, pi: OrderedTableRef[uint, PidInfo],
    statsLen: int) =
  var y = tb.getCursorYPos() + 1
  tb.write styleDim
  tb.write(offset, y, styleDim, fmt"""{"S":1}""")
  if not tui.group:
    if tui.sort == Pid: tb.write resetStyle else: tb.write styleDim
    tb.write fmt""" {"PID":>6}"""
  else:
    tb.write fmt""" {"CNT":>6}"""
  tb.write styleDim, fmt""" {"USER":<8}"""
  if tui.sort == Mem: tb.write resetStyle else: tb.write styleDim
  tb.write fmt""" {"RSS":>9} {"MEM%":>5}"""
  if tui.sort == Cpu: tb.write resetStyle else: tb.write styleDim
  tb.write fmt""" {"CPU%":>5}"""
  if tui.sort == IO: tb.write resetStyle else: tb.write styleDim
  tb.write fmt""" {"r/w IO":>9}"""
  tb.write styleDim, fmt""" {"UP":>8} {"THR":>3}"""
  if tb.width - 67 > 0:
    tb.write ' '.repeat(tb.width-67), bgNone
  inc y
  var i = 0
  tb.setStyle {}
  tb.write fgColor
  if tui.scrollY > 0:
    tb.setCursorPos (tb.width div 2)-1, tb.getCursorYPos()+1
    tb.write "..."
    inc y
    dec i
  for (_, p) in pi.pairs:
    if not tui.kernel and p.isKernel:
      continue
    if tui.filter.isSome:
      if checkFilter(tui.filter.get, p):
        continue
    elif i < tui.scrollY:
      inc i
      continue
    tb.setCursorPos offset, y
    tb.write p.state
    if tui.group:
      tb.write "    ", p.count.formatN3()
    else:
      tb.write " ", p.pid.cut(6, true, tui.scrollX)
    if p.user == "":
      tb.write " ", fgMagenta, int(p.uid).cut(8, false, tui.scrollX), fgColor
    else:
      tb.write " ", fgCyan, p.user.cut(8, false, tui.scrollX), fgColor
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write " ", p.rss.formatS().cut(9, true, tui.scrollX), bgNone
    if p.mem >= rssLimit:
      tb.write bgRed
    tb.write " ", p.mem.formatP().cut(5, true, tui.scrollX), bgNone
    if p.cpu >= cpuLimit:
      tb.write bgRed
    tb.write " ", p.cpu.formatP().cut(5, true, tui.scrollX), bgNone
    var rwStr = ""
    if p.ioReadDiff + p.ioWriteDiff > 0:
      rwStr = fmt"{formatSI(p.ioReadDiff, p.ioWriteDiff)}"
    tb.write " ", rwStr.cut(9, true, tui.scrollX)

    tb.write " ", p.uptime.formatT().cut(8, false, tui.scrollX)

    let lvl = p.parents.len
    var cmd = ""
    tb.write " ", p.threads.formatN3(), "  "
    if tui.threads and lvl > 0:
      tb.write fgCyan, repeat("·", lvl)
    if p.docker != "":
      tb.write fgBlue, p.docker & ":"
    if p.cmd != "":
      cmd.add p.cmd
    else:
      cmd.add p.name
    tb.write fgCyan, cmd.cut(tb.width - 67 - lvl - p.docker.len - 2, false,
        tui.scrollX), fgColor

    inc y
    if y > tb.height-3:
      tb.setCursorPos (tb.width div 2)-1, tb.getCursorYPos()+1
      tb.write "..."
      break

proc showFilter(tui: Tui, tb: var TerminalBuffer, cnt: int) =
  tb.setCursorPos offset, tb.height - 1
  timeButtons(tb, cnt)
  tb.write " ", HelpCol, "@", fgNone, ",", HelpCol, "#", fgNone, " - by user,docker"
  tb.write " ", HelpCol, "Esc", fgNone, ",", HelpCol, "Ret", fgNone, " - Back "
  tb.write " Filter: ", bgBlue, tui.filter.get(), bgNone

proc redraw(tui: Tui, info: FullInfoRef, stats, live: seq[StatV2]) =
  let (w, h) = terminalSize()
  var tb = newTerminalBuffer(w, h)

  if info == nil:
    tb.write fmt"blog not found {tui.blog}: {tui.hist} / {stats.len}"
    tb.display()
    return

  if checkAnyLimit(info):
    tb.setForegroundColor(fgRed, true)
    tb.drawRect(0, 0, w-1, h-1, true)

  let blogShort = extractFilename tui.blog
  tui.header(tb, info, stats.len, blogShort)
  tui.graph(tb, stats, live, blogShort)
  let pidsInfo =
    if tui.group:
      info.pidsInfo.group(tui.kernel)
    else:
      info.pidsInfo
  pidsInfo.sort(tui.sort, tui.threads)
  tui.table(tb, pidsInfo, stats.len)
  if tui.filter.isSome:
    tui.showFilter(tb, stats.len)
  else:
    tui.help(tb, w, h, stats.len)
  tb.display()

proc processKey(tui: Tui, key: Key, stats: var seq[StatV2]) =
  if key == Key.None:
    tui.refresh = true
    return
  if tui.filter.isNone:
    case key
    of Key.Escape, Key.Q: tui.quit = true
    of Key.Space: tui.draw = true
    of Key.Left:
      if tui.scrollX > 0: dec tui.scrollX
      tui.draw = true
    of Key.Right:
      inc tui.scrollX;
      tui.draw = true
    of Key.Up:
      if tui.scrollY > 0: dec tui.scrollY
      tui.draw = true
    of Key.PageUp:
      if tui.scrollY > 0: tui.scrollY -= 10
      if tui.scrollY < 0: tui.scrollY = 0
      tui.draw = true
    of Key.Down: inc tui.scrollY; tui.draw = true
    of Key.PageDown: tui.scrollY += 10; tui.draw = true
    of Key.Z: tui.scrollX = 0; tui.scrollY = 0; tui.draw = true
    of Key.P: tui.sort = Pid; tui.draw = true
    of Key.M: tui.sort = Mem; tui.draw = true
    of Key.I: tui.sort = Io; tui.draw = true
    of Key.N: tui.sort = Name; tui.draw = true
    of Key.C: tui.sort = Cpu; tui.draw = true
    of Key.T:
      tui.threads = not tui.threads
      if tui.threads: tui.group = false
      tui.draw = true
    of Key.G:
      tui.group = not tui.group
      if tui.group: tui.threads = false
      tui.draw = true
    of Key.K:
      tui.kernel = not tui.kernel
      tui.draw = true
    of Key.L: tui.forceLive = not tui.forceLive; tui.reload = true
    of Key.Slash: tui.filter = some(""); tui.draw = true
    of Key.LeftBracket:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(-1, tui.blog, tui.hist, stats.len)
      else:
        tui.forceLive = not tui.forceLive
      tui.reload = true
    of Key.RightBracket:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(+1, tui.blog, tui.hist, stats.len)
      tui.reload = true
    of Key.LeftBrace:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(-1, tui.blog, 1, stats.len)
      tui.reload = true
    of Key.RightBrace:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(+1, tui.blog, stats.len, stats.len)
      tui.reload = true
    else: discard
  else:
    case key
    of Key.Escape, Key.Enter:
      tui.filter = none(string)
      tui.draw = true
    of Key.A .. Key.Z:
      tui.filter.get().add char(key)
      tui.draw = true
    of Key.At, Key.Hash, Key.Slash, Key.Backslash, Key.Colon, Key.Space,
        Key.Minus, Key.Plus, Key.Underscore, Key.Comma, Key.Dot, Key.Ampersand:
      tui.filter.get().add char(key)
      tui.draw = true
    of Key.Zero .. Key.Nine:
      tui.filter.get().add char(key)
      tui.draw = true
    of Key.Backspace:
      if tui.filter.get().len > 0:
        tui.filter.get() = tui.filter.get[0..^2]
        tui.draw = true
    of Key.Left:
      if tui.scrollX > 0: dec tui.scrollX
      tui.draw = true
    of Key.Right:
      inc tui.scrollX;
      tui.draw = true
    of Key.LeftBracket:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(-1, tui.blog, tui.hist, stats.len)
      else:
        tui.forceLive = not tui.forceLive
      tui.reload = true
    of Key.RightBracket:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(+1, tui.blog, tui.hist, stats.len)
      tui.reload = true
    of Key.LeftBrace:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(-1, tui.blog, 1, stats.len)
      tui.reload = true
    of Key.RightBrace:
      if not tui.forceLive:
        (tui.blog, tui.hist) = moveBlog(+1, tui.blog, stats.len, stats.len)
      tui.reload = true
    else: discard


proc postProcess(tui: Tui, info: var FullInfoRef, stats, live: var seq[StatV2]) =
  if tui.refresh:
    tui.reload = true

  if tui.reload:
    if tui.hist == 0:
      tui.blog = moveBlog(+1, tui.blog, stats.len, stats.len)[0]
    if tui.refresh:
      (info, stats) = hist(tui.hist, tui.blog, live, tui.forceLive)
      tui.refresh = false
    else:
      (info, stats) = histNoLive(tui.hist, tui.blog)
    tui.reload = false
    tui.draw = true

  if tui.draw:
    tui.redraw(info, stats, live)
    tui.draw = false

iterator keyEachTimeout(refreshTimeout: int = 1000): Key =
  var timeout = refreshTimeout
  while true:
    let a = getMonoTime().ticks
    let k = getKeyWithTimeout(timeout)
    if k == Key.None:
      timeout = refreshTimeout
    else:
      let b = int((getMonoTime().ticks - a) div 1000000)
      timeout = timeout - (b mod refreshTimeout)
    yield k

when defined(debug):
  import std/enumutils
  from terminal import setForegroundColor, setBackgroundColor, setStyle

  proc colors*() =
    var i = 0
    for gCurrBg in BackgroundColor:
      for gCurrFg in ForegroundColor:
        setForegroundColor(cast[terminal.ForegroundColor](fgNone))
        setBackgroundColor(cast[terminal.BackgroundColor](bgNone))
        # stdout.write fmt"{i:>3} {gCurrBg:>14}"
        stdout.write fmt"{i:>3} "
        setForegroundColor(cast[terminal.ForegroundColor](gCurrFg))
        setBackgroundColor(cast[terminal.BackgroundColor](gCurrBg))
        stdout.write fmt"{gCurrBg:>14} "
        for s in [{}, {styleBright}, {styleDim}]:
          setStyle(s)
          stdout.write fmt""" {($gCurrFg)[2..^1] & ($s).replace("style", "")[1..^2]:>14}"""
        setForegroundColor(cast[terminal.ForegroundColor](fgNone))
        setBackgroundColor(cast[terminal.BackgroundColor](bgNone))
        echo()
        inc i

proc tui*() =
  init()
  illwillInit(fullscreen = true)
  defer: stopTui()
  setControlCHook(exitProc)
  hideCursor()

  if getCfg().light:
    fgColor = fgLightColor

  var tui = Tui(sort: Cpu)
  (tui.blog, tui.hist) = moveBlog(0, tui.blog, tui.hist, 0)
  var live = newSeq[StatV2]()
  var (info, stats) = hist(tui.hist, tui.blog, live, tui.forceLive)
  tui.redraw(info, stats, live)

  for key in keyEachTimeout(getCfg().refreshTimeout):
    tui.processKey(key, stats)
    if tui.quit:
      break
    tui.postProcess(info, stats, live)
