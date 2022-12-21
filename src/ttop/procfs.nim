import sys

import os
import strutils
from posix import Uid, getpwuid
import posix_utils
import nativesockets
import times
import tables
import sequtils

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

const MOUNT = "/proc/mounts"
const DISKSTATS = "/proc/diskstats"

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

proc checkedSub(a, b: uint): uint =
  if a > b:
    return a - b

proc parseUptime(): uint =
  let line = readLines(PROCFS & "/uptime", 1)[0]
  uint(float(hz) * line.split()[0].parseFloat())

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

proc parseStat(pid: uint, uptimeHz: uint, mem: MemInfo): PidInfo =
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
  result.uptimeHz = uptimeHz - parts[21].parseUInt()
  # result.uptimeHz = parts[21].parseInt()
  result.uptime = result.uptimeHz div uhz
  result.cpuTime = parts[13].parseUInt() + parts[14].parseUInt()
  let prevCpuTime = prevInfo.pidsInfo.getOrDefault(pid).cpuTime
  let delta =
    if pid in prevInfo.pidsInfo:
      checkedSub(result.uptimeHz, prevInfo.pidsInfo[pid].uptimeHz)
    elif prevInfo.sys != nil:
      checkedSub(uptimeHz, prevInfo.sys.uptimeHz)
    else:
      0

  result.cpu =
    if delta == 0:
      0.0
    else:
      (100.0 * checkedSub(result.cpuTime, prevCpuTime).float) / delta.float

  result.mem = float(100 * result.rss) / float(mem.MemTotal)

proc parseIO(pid: uint): (uint, uint, uint, uint) =
  let file = PROCFS & "/" & $pid & "/io"
  for line in lines(file):
    let parts = line.split(":", 1)
    case parts[0]
    of "read_bytes":
      result[0] = parseUInt parts[1].strip()
      result[2] = checkedSub(result[0], prevInfo.pidsInfo.getOrDefault(pid).ioRead)
    of "write_bytes":
      result[1] = parseUInt parts[1].strip()
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
  for line in lines(PROCFS & "/" & $pid & "/cmdline"):
    result.cmd = line.replace('\0', ' ').strip(false, true, {'\0'})
    break

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
  for line in lines(PROCFS & "/stat"):
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
        let cpu = (100 * (curTotal - curIdle).float) / curTotal.float
        result[1].add CpuInfo(total: total, idle: idle, cpu: cpu)
      else:
        let curTotal = checkedSub(total, prevInfo.cpu.total)
        let curIdle = checkedSub(idle, prevInfo.cpu.idle)
        let cpu = (100 * (curTotal - curIdle).float) / curTotal.float
        result[0] = CpuInfo(total: total, idle: idle, cpu: cpu)

proc sysInfo*(): ref SysInfo =
  new(result)
  result.datetime = times.now()
  result.hostname = getHostName()
  result.uptimeHz = parseUptime()

proc diskInfo*(dt: DateTime): OrderedTableRef[string, Disk] =
  result = newOrderedTable[string, Disk]()
  for line in lines(MOUNT):
    if line.startsWith("/dev/"):
      let parts = line.split(maxsplit = 2)
      let name = parts[0][5..^1]
      var stat: Statvfs
      assert 0 == statvfs(cstring parts[1], stat)
      result[name] = Disk(avail: stat.f_bfree * stat.f_bsize,
                          total: stat.f_blocks * stat.f_bsize,
                          path: parts[1])
  for line in lines(DISKSTATS):
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
  let file = PROCFS & "/net/dev"
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

proc sortFunc(sortOrder: SortField): auto =
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

proc sort*(info: FullInfoRef, sortOrder = Pid) =
  if sortOrder != Pid:
    sort(info.pidsInfo, sortFunc(sortOrder))


