import sys
import config

import os
import strutils
from posix import Uid, getpwuid
import posix_utils
import nativesockets
import times
import tables
import algorithm
import strscans
import options
import net
import jsony

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
  ppid*: uint
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
  parents*:seq[uint]  # generated from ppid, used to build tree
  threads*: int
  count*: int
  docker*: string

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
  pidsInfo*: OrderedTableRef[uint, PidInfo]
  disk*: OrderedTableRef[string, Disk]
  net*: OrderedTableRef[string, Net]
  temp*: Temp
  # power*: uint

type FullInfoRef* = ref FullInfo

type DockerContainer = object
  Id: string
  Names: seq[string]

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
  except CatchableError, Defect:
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
    var f: float
    doAssert scanf(line, "$f", f)
    uint(float(hz) * f)

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

    var tmp, ppid, utime, stime, starttime, vsize, rss, threads: int
    doAssert scanf(buf[1+cmdR..^1], " $w $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i $i",
                      result.state, ppid, tmp, tmp, tmp, tmp, tmp, tmp,          # 10
                      tmp, tmp, tmp, utime, stime, tmp, tmp, tmp, tmp, threads, # 20
                      tmp, starttime, vsize, rss)

    result.name.escape()
    result.pid = pid.uint
    result.ppid = ppid.uint
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
  except CatchableError:
    discard

proc devName(s: string, o: var string, off: int): int =
  while off+result < s.len:
    let c = s[off+result]
    if not (c.isAlphaNumeric or c in "-_"):
      break
    o.add c
    inc result

proc parseDocker(pid: uint, hasDocker: var bool): string =
  catchErr(file, PROCFS / $pid / "cgroup"):
    var tmp0: int
    var tmpName, dockerId: string
    for line in lines(file):
      if scanf(line, "$i:${devName}:/docker/${devName}", tmp0, tmpName, dockerId):
        hasDocker = true
        return dockerId

proc parsePid(pid: uint, uptimeHz: uint, mem: MemInfo, hasDocker: var bool): PidInfo =
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
  result.docker = parseDocker(pid, hasDocker)

iterator pids*(): uint =
  catchErr(dir, PROCFS):
    for f in walkDir(dir):
      if f.kind == pcDir:
        try:
          yield parseUInt f.path[1+PROCFSLEN..^1]
        except ValueError:
          discard

proc pidsInfo*(uptimeHz: uint, memInfo: MemInfo, hasDocker: var bool): OrderedTableRef[uint, PidInfo] =
  result = newOrderedTable[uint, PidInfo]()
  for pid in pids():
    try:
      result[pid] = parsePid(pid, uptimeHz, memInfo, hasDocker)
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
    var name: string
    var idx, v1, v2, v3, v4, v5, v6, v7, v8: int

    for line in lines(file):
      if line.startsWith("cpu"):
        doAssert scanf(line, "$w $s$i $i $i $i $i $i $i $i", name, v1, v2, v3, v4, v5, v6, v7, v8)
        let total = uint(v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8)
        let idle = uint(v4 + v5)

        if scanf(name, "cpu$i", idx):
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

proc diskInfo*(): OrderedTableRef[string, Disk] =
  result = newOrderedTable[string, Disk]()
  catchErr(file, PROCFS / "mounts"):
    for line in lines(file):
      if line.startsWith("/dev/"):
        if line.startsWith("/dev/loop"):
          continue
        let parts = line.split(maxsplit = 2)
        let name = parts[0]
        if name in result:
          continue
        let path = parts[1]
        var stat: Statvfs
        if statvfs(cstring path, stat) != 0:
          continue
        result[name] = Disk(avail: stat.f_bfree * stat.f_bsize,
                            total: stat.f_blocks * stat.f_bsize,
                            path: path)

  catchErr(file2, PROCFS / "diskstats"):
    for line in lines(file2):
      var tmp, read, write, total: int
      var name: string
      doAssert scanf(line, "$s$i $s$i ${devName} $i $i $i $i $i $i $i $i $i $i", tmp, tmp, name, tmp, tmp, tmp, read, tmp, tmp, tmp, write, tmp, total)

      if name notin result:
        continue

      let io = SECTOR * total.uint
      result[name].io = io
      result[name].ioUsage = checkedSub(io, prevInfo.disk.getOrDefault(name).io)
      let ioRead = SECTOR * read.uint
      result[name].ioRead = ioRead
      result[name].ioUsageRead = checkedSub(ioRead, prevInfo.disk.getOrDefault(name).ioRead)
      let ioWrite = SECTOR * write.uint
      result[name].ioWrite = ioWrite
      result[name].ioUsageWrite = checkedSub(ioWrite, prevInfo.disk.getOrDefault(name).ioWrite)

  return result

proc netInfo(): OrderedTableRef[string, Net] =
  result = newOrderedTable[string, Net]()
  catchErr(file, PROCFS / "net/dev"):
    var i = 0
    for line in lines(file):
      inc i
      if i in 1..2:
        continue
      var name: string
      var tmp, netIn, netOut: int
      if not scanf(line, "$s${devName}:$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i", name, netIn, tmp, tmp, tmp, tmp, tmp, tmp, tmp, netOut):
        continue
      if name.startsWith("veth"):
        continue

      result[name] = Net(
        netIn: netIn.uint,
        netInDiff: checkedSub(netIn.uint, prevInfo.net.getOrDefault(name).netIn),
        netOut: netOut.uint,
        netOutDiff: checkedSub(netOut.uint, prevInfo.net.getOrDefault(name).netOut)
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

proc getDockerContainers(): Table[string, string] =
  try:
    let socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP, false)
    socket.connectUnix(getCfg().docker)
    socket.send("GET /containers/json HTTP/1.1\nHost: v1.42\n\n")
    defer: socket.close()
    var inContent = false
    var chunked = false
    var content = ""
    while true:
      let str = socket.recvLine()
      if inContent:
        if chunked:
          let sz = fromHex[int](str)
          if sz == 0:
            break
          content.add socket.recv(sz, 100)
          inContent = false
        else:
          content.add str
          break
      elif "Transfer-Encoding: chunked" == str:
        chunked = true
      elif str == "\13\10":
        inContent = true
      elif str == "":
        break
    for c in content.fromJson(seq[DockerContainer]):
      if c.Names.len > 0:
        var name = c.Names[0]
        removePrefix(name, '/')
        result[c.Id] = name
  except CatchableError:
    discard

proc fullInfo*(prev: FullInfoRef = nil): FullInfoRef =
  result = newFullInfo()

  if prev != nil:
    prevInfo = prev

  result.sys = sysInfo()
  (result.cpu, result.cpus) = parseStat()
  result.mem = memInfo()
  var hasDocker = false
  result.pidsInfo = pidsInfo(result.sys.uptimeHz, result.mem, hasDocker)
  if hasDocker:
    let dockers = getDockerContainers()
    for pid, pi in result.pidsInfo:
      if pi.docker.len > 0:
        if pi.docker in dockers:
          result.pidsInfo[pid].docker = dockers[pi.docker]
        else:
          result.pidsInfo[pid].docker = pi.docker[0..min(11, pi.docker.high)]

  result.disk = diskInfo()
  result.net = netInfo()
  result.temp = tempInfo()
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

proc genParents(p: OrderedTableRef[uint, PidInfo]) =
  for k, v in p:
    if v.parents.len > 0:
      continue
    var s: seq[uint] = @[]
    var x = v.ppid
    while x in p:
      s.add x
      x = p[x].ppid
    let parents = s.reversed()
    p[k].parents = parents

proc sort*(info: FullInfoRef, sortOrder = Pid, threads = false, group = false) =
  if threads:
    info.pidsInfo.genParents()
    let cmpFn = sortFunc(sortOrder, false)
    info.pidsInfo.sort(proc(a, b: (uint, PidInfo)): int =
      var i = 0
      while i < a[1].parents.len and i < b[1].parents.len:
        result = cmp(a[1].parents[i], b[1].parents[i])
        if result == 0:
          inc i
        else:
          return result
      result = cmp(a[1].parents.len, b[1].parents.len)
      if result == 0:
        result = cmpFn((a[0], info.pidsInfo[a[0]]), (b[0], info.pidsInfo[b[0]]))
    )

  elif sortOrder != Pid:
    sort(info.pidsInfo, sortFunc(sortOrder))

proc id(cmd: string): string =
  let idx = cmd.find(' ')
  if idx >= 0:
    cmd[0..<idx]
  else:
    cmd

proc group*(pidsInfo: OrderedTableRef[uint, PidInfo]): OrderedTableRef[uint, PidInfo] =
  var grpInfo = initOrderedTable[string, PidInfo]()
  for _, pi in pidsInfo:
    let id = id(pi.cmd)
    var g = grpInfo.getOrDefault(id)
    if g.state == "":
      g.state = pi.state
    else:
      g.state = min(g.state, pi.state)
    if g.user == "":
      g.user = pi.user
    elif g.user != pi.user:
      g.user = "*"
    if g.uptime == 0:
      g.uptime = pi.uptime
    else:
      g.uptime = min(g.uptime, pi.uptime)
    g.name = id
    g.mem += pi.mem
    g.rss += pi.rss
    g.cpu += pi.cpu
    g.ioReadDiff += pi.ioReadDiff
    g.ioWriteDiff += pi.ioWriteDiff
    g.threads += pi.threads
    g.count.inc
    grpInfo[id] = g

  result = newOrderedTable[uint, PidInfo]()
  var i: uint = 0
  for _, gi in grpInfo:
    result[i] = gi
    inc i 

when isMainModule:
  let fi = fullInfo()
  let pi = group(fi.pidsInfo)
  fi.pidsInfo.clear()
  for o, pi in pi:
    echo o, ": ", pi.name
