import os
import strutils
import posix_utils, posix
import times
import strformat
import tables
import sequtils

const PROCFS = "/proc"
const PROCFSLEN = PROCFS.len

type SortField* = enum
  Pid, Name, Rss, Cpu

type MemInfo = object
  MemTotal: int
  MemFree: int
  MemAvailable: int
  Buffers: int
  Cached: int

type PidInfo = object
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

type SysInfo = object
  datetime*: times.DateTime
  cpu*: float
  cpus*: seq[float]

proc pidsInfo*(sortOrder = Rss): OrderedTable[uint, PidInfo]
let hz = sysconf(SC_CLK_TCK)
var prev = pidsInfo()
sleep hz

proc sysInfo*(): SysInfo
echo sysInfo()

# quit 1

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
  result = formatFloat(fbytes, format = ffDecimal, precision = 2, decimalSep = ',')
  result.trimZeros(',')
  result &= " "
  result &= prefixes[matchedIndex]
  result &= "B"

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

proc parseSize(str: string): int =
  let normStr = str.strip(true, false)
  if normStr.endsWith(" kB"):
    1024 * parseInt(normStr[0..^4])
  else:
    parseInt(normStr)

proc parseMemInfo(): MemInfo =
  for line in lines(PROCFS & "/meminfo"):
    let parts = line.split(":", 1)
    case parts[0]
    of "MemTotal": result.MemTotal = parseSize(parts[1])
    of "MemFree": result.MemFree = parseSize(parts[1])
    of "MemAvailable": result.MemAvailable = parseSize(parts[1])
    of "Buffers": result.Buffers = parseSize(parts[1])
    of "Cached": result.Cached = parseSize(parts[1])

proc parseStat(pid: uint, uptime: int, mem: MemInfo, pageSize: uint): PidInfo =
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
  let prevCpuTime = prev.getOrDefault(pid).cpuTime
  let prevUptimeHz = prev.getOrDefault(pid).uptimeHz
  result.cpu = 100 * (result.cpuTime - prevCpuTime) / (result.uptimeHz - prevUptimeHz)
  result.mem = float(100 * result.rss) / float(mem.MemTotal)

proc parsePid(pid: uint, uptime: int, mem: MemInfo, pageSize: uint): PidInfo =
  result = parseStat(pid, uptime, mem, pageSize)
  result.cmd = readLines(PROCFS & "/" & $pid & "/cmdline", 1)[0].replace('\0', ' ').strip(false, true, {'\0'})

proc pids*(): seq[uint] =
  for f in walkDir(PROCFS):
    if f.kind == pcDir:
      let fName = f.path[1+PROCFSLEN..^1]
      try:
        result.add parseUInt fName
      except:
        discard

proc sortFunc(sortOrder: SortField): auto =
  case sortOrder
  of Pid: return proc(a, b: (uint, PidInfo)): int =
                    cmp a[1].pid, b[1].pid
  of Name: return proc(a, b: (uint, PidInfo)): int =
                    cmp a[1].name, b[1].name
  of Rss: return proc(a, b: (uint, PidInfo)): int =
                    cmp b[1].rss, a[1].rss
  of Cpu: return proc(a, b: (uint, PidInfo)): int =
                    cmp b[1].cpu, a[1].cpu

proc pidsInfo*(sortOrder = Rss): OrderedTable[uint, PidInfo] =
  let pageSize = uint sysconf(SC_PAGESIZE)
  let memInfo = parseMemInfo()
  let uptime = parseUptime()
  for pid in pids():
    result[pid] = parsePid(pid, uptime, memInfo, pageSize)

  if sortOrder != Pid:
    sort(result, sortFunc(sortOrder))
  prev = result

proc parseStat(): (float, seq[float]) =
  for line in lines(PROCFS & "/stat"):
    if line.startsWith("cpu"):
      let parts = line.split()
      var off = 1
      if parts[1] == "":
        off = 2
      let all = parts[off..<off+8].map(parseInt)
      let total = all.foldl(a+b)
      let idle = all[3] + all[4]
      let cpu = 100 * (total - idle) / total
      if off == 1:
        result[1].add cpu
      else:
        result[0] = cpu

proc sysInfo*(): SysInfo =
  result.datetime = times.now()
  (result.cpu, result.cpus) = parseStat()
