import sys

import os
import strutils
from posix import Uid, getpwuid
import posix_utils
import times
import strformat
import tables
import sequtils

const PROCFS = "/proc"
const PROCFSLEN = PROCFS.len

type SortField* = enum
  Cpu, Rss, Io, Pid, Name

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
  cpuTime*: int
  cpu*: float
  mem*: float
  cmd*: string
  uptimeHz*: int
  uptime*: int
  ioRead*, ioWrite*: uint
  ioReadDiff*, ioWriteDiff*: uint

type CpuInfo = object
  total*: int
  idle*: int
  cpu*: float

type SysInfo* = object
  datetime*: times.DateTime
  cpu*: CpuInfo
  cpus*: seq[CpuInfo]

type Disk = object
  avail*: uint
  total*: uint
  io*: uint
  ioRead*: uint
  ioWrite*: uint
  ioUsage*: float
  ioUsageRead*: float
  ioUsageWrite*: float

type FullInfo* = object
  sys*: SysInfo
  mem*: MemInfo
  pidsInfo*: OrderedTable[uint, procfs.PidInfo]
  disk*: OrderedTable[string, Disk]

const MOUNT = "/proc/mounts"
const DISKSTATS = "/proc/diskstats"

proc fullInfo*(sortOrder = Pid): FullInfo
var prevInfo = fullInfo()
sleep hz

proc formatT*(ts: int): string =
  let d = initDuration(seconds = ts)
  let p = d.toParts()
  fmt"{p[Days]*24 + p[Hours]:2}:{p[Minutes]:02}:{p[Seconds]:02}"

proc formatF*(f: float): string =
  f.formatFloat(ffDecimal, 1)

proc formatU*(b: uint): string =
  let bytes = int b
  var
    xb: int64 = bytes
    fbytes: float
    lastXb: int64 = bytes
    matchedIndex = 0
    prefixes: array[9, string] = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
  for index in 1..<prefixes.len:
    lastXb = xb
    xb = bytes div (1'i64 shl (index*10))
    matchedIndex = index
    if xb == 0:
      xb = lastXb
      matchedIndex = index - 1
      break
  fbytes = bytes.float / (1'i64 shl (matchedIndex*10)).float
  result = formatFloat(fbytes, format = ffDecimal, precision = 2, decimalSep = '.')
  result.trimZeros(',')
  result &= " "
  result &= prefixes[matchedIndex]
  result &= "B"

proc formatUU*(b: uint): string =
  let bytes = int b
  var
    xb: int64 = bytes
    fbytes: float
    lastXb: int64 = bytes
    matchedIndex = 0
    prefixes: array[9, string] = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
  for index in 1..<prefixes.len:
    lastXb = xb
    xb = bytes div (1'i64 shl (index*10))
    matchedIndex = index
    if xb == 0:
      xb = lastXb
      matchedIndex = index - 1
      break
  fbytes = bytes.float / (1'i64 shl (matchedIndex*10)).float
  result = formatFloat(fbytes, format = ffDecimal, precision = 2, decimalSep = '.')
  result.trimZeros(',')

proc cut*(str: string, size: int, right: bool, scroll: int): string =
  let l = len(str)
  if l > size:
    let max = min(size+scroll, str.high)
    if max >= str.high:
      str[^size..max] & ' '
    else:
        str[scroll..<max] & "."
  else:
    if right:
      ' '.repeat(size - l) & str
    else:
      str & ' '.repeat(1 + size - l)

proc cut*(i: int | uint, size: int, right: bool, scroll: int): string =
  cut($i, size, right, scroll)

proc parseUptime(): int =
  let line = readLines(PROCFS & "/uptime", 1)[0]
  int float(hz) * line.split()[0].parseFloat()

proc parseSize(str: string): uint =
  let normStr = str.strip(true, false)
  if normStr.endsWith(" kB"):
    1024 * parseUInt(normStr[0..^4])
  else:
    parseUInt(normStr)

proc memInfo(): MemInfo =
  for line in lines(PROCFS & "/meminfo"):
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

proc parseStat(pid: uint, uptime: int, mem: MemInfo): PidInfo =
  let file = PROCFS & "/" & $pid & "/stat"
  let stat = stat(file)
  result.uid = stat.st_uid
  let userInfo = getpwuid(result.uid)
  if not isNil userInfo:
    result.user = $(userInfo.pw_name)
  let line = readLines(file, 1)[0]
  let parts = line.split()
  result.pid = parts[0].parseUInt()
  result.name = parts[1][1..^2]
  result.state = parts[2]
  result.vsize = parts[22].parseUInt()
  result.rss = pageSize * parts[23].parseUInt()
  result.uptimeHz = uptime - parts[21].parseInt()
  # result.uptimeHz = parts[21].parseInt()
  result.uptime = result.uptimeHz div hz
  result.cpuTime = parts[13].parseInt() + parts[14].parseInt()
  let prevCpuTime = prevInfo.pidsInfo.getOrDefault(pid).cpuTime
  let prevUptimeHz = prevInfo.pidsInfo.getOrDefault(pid).uptimeHz
  result.cpu = 100 * (result.cpuTime - prevCpuTime) / (result.uptimeHz - prevUptimeHz)
  result.mem = float(100 * result.rss) / float(mem.MemTotal)

proc parseIO(pid: uint): (uint, uint, uint, uint) =
  let file = PROCFS & "/" & $pid & "/io"
  for line in lines(file):
    let parts = line.split(":", 1)
    case parts[0]
    of "rchar":
      result[0] = parseUInt parts[1].strip()
      result[2] = result[0] - prevInfo.pidsInfo.getOrDefault(pid).ioRead
    of "wchar":
      result[1] = parseUInt parts[1].strip()
      result[3] = result[1] - prevInfo.pidsInfo.getOrDefault(pid).ioWrite

proc parsePid(pid: uint, uptime: int, mem: MemInfo): PidInfo =
  result = parseStat(pid, uptime, mem)
  try:
    let io = parseIO(pid)
    result.ioRead = io[0]
    result.ioReadDiff = io[2]
    result.ioWrite = io[1]
    result.ioWriteDiff = io[3]
  except IOError:
    discard
  result.cmd = readLines(PROCFS & "/" & $pid & "/cmdline", 1)[0].replace('\0', ' ').strip(false, true, {'\0'})

proc pids*(): seq[uint] =
  for f in walkDir(PROCFS):
    if f.kind == pcDir:
      let fName = f.path[1+PROCFSLEN..^1]
      try:
        result.add parseUInt fName
      except ValueError:
        discard

proc sortFunc(sortOrder: SortField): auto =
  case sortOrder
  of Pid: return proc(a, b: (uint, PidInfo)): int =
                    cmp a[1].pid, b[1].pid
  of Name: return proc(a, b: (uint, PidInfo)): int =
                    cmp a[1].name, b[1].name
  of Rss: return proc(a, b: (uint, PidInfo)): int =
                    cmp b[1].rss, a[1].rss
  of Io: return proc(a, b: (uint, PidInfo)): int =
                    cmp b[1].ioReadDiff+b[1].ioWriteDiff, a[1].ioReadDiff+a[1].ioWriteDiff
  of Cpu: return proc(a, b: (uint, PidInfo)): int =
                    cmp b[1].cpu, a[1].cpu

proc pidsInfo*(sortOrder: SortField, memInfo: MemInfo): OrderedTable[uint, PidInfo] =
  let uptime = parseUptime()
  for pid in pids():
    try:
      result[pid] = parsePid(pid, uptime, memInfo)
    except OSError:
      if osLastError() != OSErrorCode(2):
        raise

  if sortOrder != Pid:
    sort(result, sortFunc(sortOrder))

proc getOrDefault(s: seq[CpuInfo], i: int): CpuInfo =
  if i < s.len:
    return s[i]

proc parseStat(): (CpuInfo, seq[CpuInfo]) =
  for line in lines(PROCFS & "/stat"):
    if line.startsWith("cpu"):
      let parts = line.split()
      var off = 1
      if parts[1] == "":
        off = 2
      let all = parts[off..<off+8].map(parseInt)
      let total = all.foldl(a+b)
      let idle = all[3] + all[4]
      if off == 1:
        let curTotal = total - prevInfo.sys.cpus.getOrDefault(result[1].len).total
        let curIdle = idle - prevInfo.sys.cpus.getOrDefault(result[1].len).idle
        let cpu = 100 * (curTotal - curIdle) / curTotal
        result[1].add CpuInfo(total: total, idle: idle, cpu: cpu)
      else:
        let curTotal = total - prevInfo.sys.cpu.total
        let curIdle = idle - prevInfo.sys.cpu.idle
        let cpu = 100 * (curTotal - curIdle) / curTotal
        result[0] = CpuInfo(total: total, idle: idle, cpu: cpu)

proc sysInfo*(): SysInfo =
  result.datetime = times.now()
  (result.cpu, result.cpus) = parseStat()

proc diskInfo*(dt: DateTime): OrderedTable[string, Disk] =
  var result = initOrderedTable[string, Disk]()
  for line in lines(MOUNT):
    if line.startsWith("/dev/"):
      let parts = line.split(maxsplit = 2)
      let name = parts[0][5..^1]
      var stat: Statvfs
      assert 0 == statvfs(cstring parts[1], stat)
      result[name] = Disk(avail: stat.f_bfree * stat.f_bsize, total: stat.f_blocks * stat.f_bsize)
  for line in lines(DISKSTATS):
    let parts = line.splitWhitespace()
    let name = parts[2]
    if name in result:
      let msPassed = (dt - prevInfo.sys.datetime).inMilliseconds()
      let io = parseUInt parts[12]
      result[name].io = io
      result[name].ioUsage = 100 * float(io - prevInfo.disk.getOrDefault(name).io) / float msPassed
      let ioRead = parseUInt parts[6]
      result[name].ioRead = ioRead
      result[name].ioUsageRead = 100 * float(ioRead - prevInfo.disk.getOrDefault(name).ioRead) / float msPassed
      let ioWrite = parseUInt parts[10]
      result[name].ioWrite = ioWrite
      result[name].ioUsageWrite = 100 * float(ioWrite - prevInfo.disk.getOrDefault(name).ioWrite) / float msPassed
  return result

proc fullInfo*(sortOrder = Pid): FullInfo =
  result.sys = sysInfo()
  result.mem = memInfo()
  result.pidsInfo = pidsInfo(sortOrder, result.mem)
  result.disk = diskInfo(result.sys.datetime)
  prevInfo = result
