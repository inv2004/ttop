import sys

import os
import strutils
from posix import Uid, getpwuid
import posix_utils
import nativesockets
import times
import tables
import sequtils
import strscans
import options

const PROCFS = "/proc"
const PROCFSLEN = PROCFS.len
const SECTOR = 512
var uhz = hz.uint

const MIN_TEMP = -300000

type ParseInfoError* = object of ValueError
  file*: string

type SortField* = enum
  Cpu, Mem, Io, Pid, Name

type MemInfo* = object
  MemTotal*: uint
  MemFree*: uint
  MemDiff*: int
  MemAvailable*: uint
  Buffers*: uint
  Cached*: uint
  SwapTotal*: uint
  SwapFree*: uint

type PidInfo* = object
  pid*: uint
  uid*: Uid
  user*: string
  name*: string
  state*: string
  vsize*: uint
  rss*: uint
  cpuTime*: uint
  cpu*: float
  mem*: float
  cmd*: string
  uptimeHz*: uint
  uptime*: uint
  ioRead*, ioWrite*: uint
  ioReadDiff*, ioWriteDiff*: uint
  netIn*, netOut*: uint
  netInDiff*, netOutDiff*: uint
  children*: seq[uint]
  threads*: int
  lvl*: int
  ord*: int

type CpuInfo* = object
  total*: uint
  idle*: uint
  cpu*: float

type SysInfo* = object
  datetime*: times.DateTime
  hostname*: string
  uptimeHz*: uint

type Disk* = object
  avail*: uint
  total*: uint
  io*: uint
  ioRead*: uint
  ioWrite*: uint
  ioUsage*: uint
  ioUsageRead*: uint
  ioUsageWrite*: uint
  path*: string

type Net = object
  netIn*: uint
  netInDiff*: uint
  netOut*: uint
  netOutDiff*: uint

type Temp* = object
  cpu*: Option[float64]
  nvme*: Option[float64]

type FullInfo* = object
  sys*: ref SysInfo
  cpu*: CpuInfo
  cpus*: seq[CpuInfo]
  mem*: MemInfo
  pidsInfo*: OrderedTableRef[uint, procfs.PidInfo]
  disk*: OrderedTableRef[string, Disk]
  net*: OrderedTableRef[string, Net]
  temp*: Temp
  # power*: uint

type FullInfoRef* = ref FullInfo

proc newParseInfoError(file: string, parent: ref Exception): ref ParseInfoError =
  let parentMsg = if parent != nil: parent.msg else: "nil"
  var msg = "error during parsing " & file & ": " & parentMsg
  newException(ParseInfoError, msg, parent)

proc newFullInfo(): FullInfoRef =
  new(result)
  result.pidsInfo = newOrderedTable[uint, procfs.PidInfo]()
  result.disk = newOrderedTable[string, Disk]()
  result.net = newOrderedTable[string, Net]()

proc fullInfo*(prev: FullInfoRef = nil): FullInfoRef

var prevInfo = newFullInfo()

template catchErr(file: untyped, filename: string, body: untyped) =
  let file: string = filename
  try:
    body
  except:
    raise newParseInfoError(file, getCurrentException())

proc init*() =
  prevInfo = fullInfo()
  sleep hz

proc cut*(str: string, size: int, right: bool, scroll: int): string =
  let l = len(str)
  if l > size:
    let max = min(size+scroll, str.high)
    if max >= str.high:
      str[^size..max]
    elif max - 1 > 0:
      if scroll > 0:
        "." & str[scroll+1..<max-1] & "."
      else:
        str[0..<max-1] & "."
    else:
      ""
  else:
    if right:
      ' '.repeat(size - l) & str
    else:
      str & ' '.repeat(size - l)

proc cut*(i: int | uint, size: int, right: bool, scroll: int): string =
  cut($i, size, right, scroll)

proc escape(s: var string) =
  for c in s.mitems():
    case c
    of '\0'..'\31', '\127': c = '?'
    else: discard

proc checkedSub*(a, b: uint): uint =
  if a > b:
    return a - b

proc checkedDiv*(a, b: uint): float =
  if b != 0:
    return a.float / b.float

proc parseUptime(): uint =
  catchErr(file, PROCFS / "uptime"):
    let line = readLines(file, 1)[0]
    uint(float(hz) * line.split()[0].parseFloat())

proc parseSize(str: string): uint =
  let normStr = str.strip(true, false)
  if normStr.endsWith(" kB"):
    1024 * parseUInt(normStr[0..^4])
  elif normStr.endsWith(" mB"):
    1024 * 1024 * parseUInt(normStr[0..^4])
  elif normStr.endsWith("B"):
    raise newException(ValueError, "cannot parse: " & normStr)
  else:
    parseUInt(normStr)

proc memInfo(): MemInfo =
  catchErr(file, PROCFS / "meminfo"):
    for line in lines(file):
      let parts = line.split(":", 1)
      case parts[0]
      of "MemTotal": result.MemTotal = parseSize(parts[1])
      of "MemFree": result.MemFree = parseSize(parts[1])
      of "MemAvailable": result.MemAvailable = parseSize(parts[1])
      of "Buffers": result.Buffers = parseSize(parts[1])
      of "Cached": result.Cached = parseSize(parts[1])
      of "SwapTotal": result.SwapTotal = parseSize(parts[1])
      of "SwapFree": result.SwapFree = parseSize(parts[1])
    result.MemDiff = int(result.MemFree) - int(prevInfo.mem.MemFree)

proc parseTasks(pid: uint): seq[uint] =
  catchErr(file, PROCFS / $pid / "task/*/children"):
    for c in walkFiles(file):
      for line in lines(c):
        if line.len > 0:
          result.add line.strip(false, true, chars = {' ', '\n', '\x00'}).split().map(parseUInt)
        break

proc parseStat(pid: uint, uptimeHz: uint, mem: MemInfo): PidInfo =
  catchErr(file, PROCFS / $pid / "stat"):
    let stat = stat(file)
    result.uid = stat.st_uid
    let userInfo = getpwuid(result.uid)
    if not isNil userInfo:
      result.user = $(userInfo.pw_name)
    let buf = readFile(file)

    let cmdL = buf.find('(')
    let cmdR = buf.rfind(')')

    var pid: int
    doAssert scanf(buf[0..<cmdL], "$i", pid)
    result.name = buf[1+cmdL..<cmdR]

    var tmp, utime, stime, starttime, vsize, rss, threads: int
    doAssert scanf(buf[1+cmdR..^1], " $w $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i",
              result.state, tmp, tmp, tmp, tmp, tmp, tmp, tmp, # 10
      tmp, tmp, tmp, utime, stime, tmp, tmp, tmp, tmp, threads, # 20
      tmp, starttime, vsize, rss)

    result.name.escape()
    result.pid = pid.uint
    result.vsize = vsize.uint
    result.rss = pageSize * rss.uint
    result.threads = threads
    result.uptimeHz = uptimeHz - starttime.uint
    result.uptime = result.uptimeHz div uhz
    result.cpuTime = utime.uint + stime.uint

    let prevCpuTime = prevInfo.pidsInfo.getOrDefault(result.pid).cpuTime
    let delta =
      if result.pid in prevInfo.pidsInfo:
        checkedSub(result.uptimeHz, prevInfo.pidsInfo[result.pid].uptimeHz)
      elif prevInfo.sys != nil:
        checkedSub(uptimeHz, prevInfo.sys.uptimeHz)
      else:
        0

    result.cpu = checkedDiv(100 * checkedSub(result.cpuTime, prevCpuTime), delta)
    result.mem = checkedDiv(100 * result.rss, mem.MemTotal)

    result.children = parseTasks(result.pid)

proc parseIO(pid: uint): (uint, uint, uint, uint) =
  catchErr(file, PROCFS / $pid / "io"):
    var name: string;
    var val: int;
    for line in lines(file):
      doAssert scanf(line, "$w: $i", name, val)
      case name
      of "read_bytes":
        result[0] = val.uint
        result[2] = checkedSub(result[0], prevInfo.pidsInfo.getOrDefault(pid).ioRead)
      of "write_bytes":
        result[1] = val.uint
        result[3] = checkedSub(result[1], prevInfo.pidsInfo.getOrDefault(pid).ioWrite)

proc parseCmd(pid: uint): string =
  let file = PROCFS / $pid / "cmdline"
  try:
    let buf = readFile(file)
    result = buf.strip(false, true, {'\0'}).replace('\0', ' ')
    result.escape()
  except:
    discard

proc parsePid(pid: uint, uptimeHz: uint, mem: MemInfo): PidInfo =
  try:
    result = parseStat(pid, uptimeHz, mem)
    let io = parseIO(pid)
    result.ioRead = io[0]
    result.ioReadDiff = io[2]
    result.ioWrite = io[1]
    result.ioWriteDiff = io[3]
  except ParseInfoError:
    let ex = getCurrentException()
    if ex.parent of IOError:
      result.cmd = "IOError"
    else:
      raise
  result.cmd = parseCmd(pid)

proc pids*(): seq[uint] =
  catchErr(dir, PROCFS):
    for f in walkDir(dir):
      if f.kind == pcDir:
        let fName = f.path[1+PROCFSLEN..^1]
        try:
          result.add parseUInt fName
        except ValueError:
          discard

proc pidsInfo*(uptimeHz: uint, memInfo: MemInfo): OrderedTableRef[uint, PidInfo] =
  result = newOrderedTable[uint, PidInfo]()
  for pid in pids():
    try:
      result[pid] = parsePid(pid, uptimeHz, memInfo)
    except ParseInfoError:
      let ex = getCurrentException()
      if ex.parent of OSError:
        if osLastError() != OSErrorCode(2):
          raise
      else:
        raise

proc getOrDefault(s: seq[CpuInfo], i: int): CpuInfo =
  if i < s.len:
    return s[i]

proc parseStat(): (CpuInfo, seq[CpuInfo]) =
  catchErr(file, PROCFS / "stat"):
    for line in lines(file):
      if line.startsWith("cpu"):
        let parts = line.split()
        var off = 1
        if parts[1] == "":
          off = 2
        let all = parts[off..<off+8].map(parseUInt)
        let total = all.foldl(a+b)
        let idle = all[3] + all[4]
        if off == 1:
          let curTotal = checkedSub(total, prevInfo.cpus.getOrDefault(result[1].len).total)
          let curIdle = checkedSub(idle, prevInfo.cpus.getOrDefault(result[1].len).idle)
          let cpu = checkedDiv(100 * (curTotal - curIdle), curTotal)
          result[1].add CpuInfo(total: total, idle: idle, cpu: cpu)
        else:
          let curTotal = checkedSub(total, prevInfo.cpu.total)
          let curIdle = checkedSub(idle, prevInfo.cpu.idle)
          let cpu = checkedDiv(100 * (curTotal - curIdle), curTotal)
          result[0] = CpuInfo(total: total, idle: idle, cpu: cpu)

proc sysInfo*(): ref SysInfo =
  new(result)
  result.datetime = times.now()
  result.hostname = getHostName()
  result.uptimeHz = parseUptime()

proc diskInfo*(dt: DateTime): OrderedTableRef[string, Disk] =
  result = newOrderedTable[string, Disk]()
  catchErr(file, PROCFS / "mounts"):
    for line in lines(file):
      if line.startsWith("/dev/"):
        if line.startsWith("/dev/loop"):
          continue
        let parts = line.split(maxsplit = 2)
        let name = parts[0]
        let path = parts[1]
        var stat: Statvfs
        if statvfs(cstring path, stat) != 0:
          continue
        result[name] = Disk(avail: stat.f_bfree * stat.f_bsize,
                            total: stat.f_blocks * stat.f_bsize,
                            path: path)

  catchErr(file2, PROCFS / "diskstats"):
    for line in lines(file2):
      let parts = line.splitWhitespace()
      let name = parts[2]
      if name in result:
        # let msPassed = (dt - prevInfo.sys.datetime).inMilliseconds()
        let io = SECTOR * parseUInt parts[12]
        result[name].io = io
        # result[name].ioUsage = 100 * float(io - prevInfo.disk.getOrDefault(
        #     name).io) / float msPassed
        result[name].ioUsage = checkedSub(io, prevInfo.disk.getOrDefault(name).io)
        let ioRead = SECTOR * parseUInt parts[6]
        result[name].ioRead = ioRead
        # result[name].ioUsageRead = 100 * float(ioRead -
        #     prevInfo.disk.getOrDefault(name).ioRead) / float msPassed
        result[name].ioUsageRead = checkedSub(ioRead,
            prevInfo.disk.getOrDefault(name).ioRead)
        let ioWrite = SECTOR * parseUInt parts[10]
        result[name].ioWrite = ioWrite
        # result[name].ioUsageWrite = 100 * float(ioWrite -
        #     prevInfo.disk.getOrDefault(name).ioWrite) / float msPassed
        result[name].ioUsageWrite = checkedSub(ioWrite,
            prevInfo.disk.getOrDefault(name).ioWrite)

  return result

proc netInfo(): OrderedTableRef[string, Net] =
  result = newOrderedTable[string, Net]()
  catchErr(file, PROCFS / "net/dev"):
    for line in lines(file):
      let parts = line.split(":", 1)
      if parts.len == 2:
        let name = parts[0].strip()
        let fields = parts[1].splitWhitespace()
        let netIn = parseUInt fields[0]
        let netOut = parseUInt fields[8]
        result[name] = Net(
          netIn: netIn,
          netInDiff: checkedSub(netIn, prevInfo.net.getOrDefault(name).netIn),
          netOut: netOut,
          netOutDiff: checkedSub(netOut, prevInfo.net.getOrDefault(name).netOut)
        )

proc findMaxTemp(dir: string): Option[float64] =
  var maxTemp = MIN_TEMP
  for file in walkFiles(dir /../ "temp*_input"):
    for line in lines(file):
      let temp = parseInt(line)
      if temp > maxTemp:
        maxTemp = temp
      break
  if maxTemp != MIN_TEMP:
    return some(maxTemp / 1000)

proc tempInfo(): Temp =
  var cnt = 0
  for file in walkFiles("/sys/class/hwmon/hwmon*/name"):
    case readFile(file)
    of "coretemp\n", "k10temp\n":
      result.cpu = findMaxTemp(file)
      cnt.inc
      if cnt == 2: break
    of "nvme\n":
      result.nvme = findMaxTemp(file)
      cnt.inc
      if cnt == 2: break
    else:
      discard

# proc powerInfo(): uint =
#   for f in walkFiles("/sys/class/power_supply/BAT*/power_now"):
#     for line in lines(f):
#       result += parseUInt(line)

proc fullInfo*(prev: FullInfoRef = nil): FullInfoRef =
  result = newFullInfo()

  if prev != nil:
    prevInfo = prev

  result.sys = sysInfo()
  (result.cpu, result.cpus) = parseStat()
  result.mem = memInfo()
  result.pidsInfo = pidsInfo(result.sys.uptimeHz, result.mem)
  result.disk = diskInfo(result.sys.datetime)
  result.net = netInfo()
  result.temp = tempInfo()
  # result.power = powerInfo()
  prevInfo = result

proc sortFunc(sortOrder: SortField, threads = false): auto =
  case sortOrder
  of Pid: return proc(a, b: (uint, PidInfo)): int =
    cmp a[1].pid, b[1].pid
  of Name: return proc(a, b: (uint, PidInfo)): int =
    cmp a[1].name, b[1].name
  of Mem: return proc(a, b: (uint, PidInfo)): int =
    cmp b[1].rss, a[1].rss
  of Io: return proc(a, b: (uint, PidInfo)): int =
    cmp b[1].ioReadDiff+b[1].ioWriteDiff, a[1].ioReadDiff+a[1].ioWriteDiff
  of Cpu: return proc(a, b: (uint, PidInfo)): int =
    cmp b[1].cpu, a[1].cpu

proc mkTree(p: uint, pp: OrderedTableRef[uint, PidInfo], lvl, i: int,
     sortOrder: SortField): int =

  result = i

  let o = newOrderedTable[uint, PidInfo]()
  for c in pp[p].children:
    if c in pp:
      o[c] = pp[c]

  sort(o, sortFunc(sortOrder))

  pp[p].lvl = lvl
  pp[p].ord = result
  inc result
  for c in o.keys():
    result = mkTree(c, pp, 1+lvl, result, sortOrder)
    inc result

proc sort*(info: FullInfoRef, sortOrder = Pid, threads = false) =
  if threads:
    var r = 0
    for p, v in info.pidsInfo:
      if v.ord == 0:
        r = mkTree(p, info.pidsInfo, 0, r, sortOrder)
    sort(info.pidsInfo, proc(a, b: (uint, PidInfo)): int =
      cmp(a[1].ord, b[1].ord)
    )
  elif sortOrder != Pid:
    sort(info.pidsInfo, sortFunc(sortOrder))

when isMainModule:
  let s = "a:   100"
  let fs = s.split(":", 1)
  echo fs
  echo parseSize(fs[1])

