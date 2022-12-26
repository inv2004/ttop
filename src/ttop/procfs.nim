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

const PROCFS = "/proc"
const PROCFSLEN = PROCFS.len
const SECTOR = 512
var uhz = hz.uint

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

type CpuInfo = object
  total*: uint
  idle*: uint
  cpu*: float

type SysInfo* = object
  datetime*: times.DateTime
  hostname*: string
  uptimeHz*: uint

type Disk = object
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

type FullInfo* = object
  sys*: ref SysInfo
  cpu*: CpuInfo
  cpus*: seq[CpuInfo]
  mem*: MemInfo
  pidsInfo*: OrderedTableRef[uint, procfs.PidInfo]
  disk*: OrderedTableRef[string, Disk]
  net*: OrderedTableRef[string, Net]

type FullInfoRef* = ref FullInfo

proc newFullInfo(): FullInfoRef =
  new(result)
  result.pidsInfo = newOrderedTable[uint, procfs.PidInfo]()
  result.disk = newOrderedTable[string, Disk]()
  result.net = newOrderedTable[string, Net]()

proc fullInfo*(prev: FullInfoRef = nil): FullInfoRef

var prevInfo = newFullInfo()

proc init*() =
  prevInfo = fullInfo()
  sleep hz

proc cut*(str: string, size: int, right: bool, scroll: int): string =
  let l = len(str)
  if l > size:
    let max = min(size+scroll, str.high)
    if max >= str.high:
      str[^size..max]
    else:
      if scroll > 0:
        "." & str[scroll+1..<max-1] & "."
      else:
        str[0..<max-1] & "."
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

proc checkedSub(a, b: uint): uint =
  if a > b:
    return a - b

proc checkedDiv(a, b: uint): float =
  if b != 0:
    return a.float / b.float

proc parseUptime(): uint =
  let line = readLines(PROCFS / "uptime", 1)[0]
  uint(float(hz) * line.split()[0].parseFloat())

proc parseSize(str: string): uint =
  let normStr = str.strip(true, false)
  if normStr.endsWith(" kB"):
    1024 * parseUInt(normStr[0..^4])
  else:
    parseUInt(normStr)

proc memInfo(): MemInfo =
  for line in lines(PROCFS / "meminfo"):
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
  for c in walkFiles(PROCFS / $pid / "task/*/children"):
    for line in lines(c):
      if line.len > 0:
        result.add line[0..^2].split().map(parseUInt)
      break

proc parseStat(pid: uint, uptimeHz: uint, mem: MemInfo): PidInfo =
  let file = PROCFS / $pid / "stat"
  let stat = stat(file)
  result.uid = stat.st_uid
  let userInfo = getpwuid(result.uid)
  if not isNil userInfo:
    result.user = $(userInfo.pw_name)
  let buf = readFile(file)

  var pid, tmp, utime, stime, starttime, vsize, rss, threads: int
  if not scanf(buf, "$i ($+) $w $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i",
            pid, result.name, result.state, tmp, tmp, tmp, tmp, tmp, tmp, tmp, # 10
    tmp, tmp, tmp, utime, stime, tmp, tmp, tmp, tmp, threads, # 20
    tmp, starttime, vsize, rss):
      raise newException(ValueError, "cannot parse " & file)

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
  let file = PROCFS / $pid / "io"
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

proc parsePid(pid: uint, uptimeHz: uint, mem: MemInfo): PidInfo =
  result = parseStat(pid, uptimeHz, mem)
  try:
    let io = parseIO(pid)
    result.ioRead = io[0]
    result.ioReadDiff = io[2]
    result.ioWrite = io[1]
    result.ioWriteDiff = io[3]
  except IOError:
    discard
  let buf = readFile(PROCFS / $pid / "cmdline")
  result.cmd = buf.strip(false, true, {'\0'}).replace('\0', ' ')
  result.cmd.escape()

proc pids*(): seq[uint] =
  for f in walkDir(PROCFS):
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
    except OSError:
      if osLastError() != OSErrorCode(2):
        raise

proc getOrDefault(s: seq[CpuInfo], i: int): CpuInfo =
  if i < s.len:
    return s[i]

proc parseStat(): (CpuInfo, seq[CpuInfo]) =
  for line in lines(PROCFS / "stat"):
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
  for line in lines(PROCFS / "mounts"):
    if line.startsWith("/dev/"):
      let parts = line.split(maxsplit = 2)
      let name = parts[0]
      let path = parts[1]
      var stat: Statvfs
      if statvfs(cstring path, stat) != 0:
        continue
      result[name] = Disk(avail: stat.f_bfree * stat.f_bsize,
                          total: stat.f_blocks * stat.f_bsize,
                          path: path)
  for line in lines(PROCFS / "diskstats"):
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
      result[name].ioUsageRead = checkedSub(ioRead, prevInfo.disk.getOrDefault(name).ioRead)
      let ioWrite = SECTOR * parseUInt parts[10]
      result[name].ioWrite = ioWrite
      # result[name].ioUsageWrite = 100 * float(ioWrite -
      #     prevInfo.disk.getOrDefault(name).ioWrite) / float msPassed
      result[name].ioUsageWrite = checkedSub(ioWrite,
          prevInfo.disk.getOrDefault(name).ioWrite)
  return result

proc netInfo(): OrderedTableRef[string, Net] =
  result = newOrderedTable[string, Net]()
  let file = PROCFS / "net/dev"
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
  let info = fullInfo()
  sort(info, Mem, true)
  for k, t in info.pidsInfo:
    echo k, ": ", t.ord
