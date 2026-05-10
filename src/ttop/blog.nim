import procfs
import config

import marshal
import zippy
import streams
import tables
import times
import os
import sequtils
import algorithm
import jsony
import strformat
import strutils

type StatV1* = object
  prc*: int
  cpu*: float
  mem*: uint
  io*: uint

type StatV2* = object
  prc*: int
  cpu*: float
  memTotal*: uint
  memAvailable*: uint
  io*: uint
  netIn*: uint
  netOut*: uint

proc toStatV2(a: StatV1): StatV2 =
  result.prc = a.prc
  result.cpu = a.cpu
  result.io = a.io

const TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:sszzz"

proc dumpHook*(s: var string, v: DateTime) =
  s.add '"' & v.format(TIME_FORMAT) & '"'

proc parseHook*(s: string, i: var int, v: var DateTime) =
  var str: string
  parseHook(s, i, str)
  v = parse(str, TIME_FORMAT)

proc flock(fd: FileHandle, op: int): int {.header: "<sys/file.h>",
    importc: "flock".}

proc genStat(f: FullInfoRef): StatV2 =
  var io: uint = 0
  for _, disk in f.disk:
    io += disk.ioUsageRead + disk.ioUsageWrite

  var netIn: uint = 0
  var netOut: uint = 0
  for _, net in f.net:
    netIn += net.netInDiff
    netOut += net.netOutDiff

  StatV2(
    prc: f.pidsInfo.len,
    cpu: f.cpu.cpu,
    memTotal: f.mem.MemTotal,
    memAvailable: f.mem.MemAvailable,
    io: io,
    netIn: netIn,
    netOut: netOut
  )

proc saveStat*(s: FileStream, f: FullInfoRef) =
  var stat = genStat(f)

  let sz = sizeof(StatV2)
  s.write sz.uint32
  s.writeData stat.addr, sz

const STATV2_OLD_SIZE = sizeof(StatV2) - 2 * sizeof(uint)

proc stat(s: FileStream): StatV2 =
  let sz = s.readUInt32().int
  var rsz: int
  case sz
  of sizeof(StatV2):
    rsz = s.readData(result.addr, sizeof(StatV2))
    doAssert sz == rsz
  of STATV2_OLD_SIZE:
    var buf = newSeq[byte](STATV2_OLD_SIZE)
    rsz = s.readData(buf[0].addr, STATV2_OLD_SIZE)
    doAssert sz == rsz
    copyMem(result.addr, buf[0].addr, STATV2_OLD_SIZE)
  of sizeof(StatV1):
    var sv1: StatV1
    rsz = s.readData(sv1.addr, sizeof(StatV1))
    doAssert sz == rsz
    result = toStatV2 sv1
  else:
    discard

proc infoFromGzip(buf: string): FullInfo =
  let jsonStr = uncompress(buf)
  try:
    return jsonStr.fromJson(FullInfo)
  except JsonError:
    return to[FullInfo](jsonStr)

type NetHistory* = OrderedTableRef[string, tuple[inData: seq[uint], outData: seq[uint]]]

# Full cache for a single blog file. Only one blog file is cached at a time -
# when the user navigates to a different file the entire cache is dropped and
# rebuilt. This avoids re-reading and re-decompressing the blog file on every
# navigation keystroke within the same file.
#
# On cache hit (same blog file): stats and netHistory come from memory with zero
# file I/O; only the single compressed JSON blob at position ii is decompressed
# to produce the FullInfo for that snapshot.
#
# On cache miss (different file or first access): the entire blog file is read
# once, all JSON blobs are decompressed, and the cache is populated.
type BlogCache* = object
  blog*: string               # blog filename this cache belongs to
  stats*: seq[StatV2]         # all binary StatV2 records from the file
  netHistory*: NetHistory     # per-interface network delta time-series
  blobs*: seq[string]         # compressed JSON blobs (for FullInfo at position ii)
  broken*: bool               # true if the file was corrupt / truncated

var blogCache*: BlogCache

proc hist*(ii: int, blog: string, live: var seq[StatV2], forceLive: bool): (FullInfoRef, seq[StatV2], bool) =
  let fi = fullInfo()
  if ii == 0 or forceLive:
    result[0] = fi
  live.add genStat(fi)

  live.delete((0..live.high - 1000))

  # In live mode we never need the blog cache — the graph uses info.net[netIf]
  # directly from the current fullInfo(). Return early to skip all file I/O.
  if forceLive or ii == 0:
    return

  # Historical mode: check the cache first.
  if blogCache.blog == blog and blogCache.stats.len > 0:
    # Cache hit — everything is already in memory, no file I/O needed.
    result[1] = blogCache.stats
    result[2] = blogCache.broken

    # Only decompress the single JSON blob the user is currently viewing.
    if blogCache.blobs.len > 0:
      if ii > 0 and ii <= blogCache.blobs.len:
        new(result[0])
        result[0][] = infoFromGzip(blogCache.blobs[ii - 1])
      elif ii == -1 and blogCache.blobs.len > 0:
        new(result[0])
        result[0][] = infoFromGzip(blogCache.blobs[^1])
    return

  # Cache miss — read the entire blog file, decompress all records, and
  # build the cache entries for stats, netHistory, and compressed blobs.
  var netHistory = newOrderedTable[string, tuple[inData: seq[uint], outData: seq[uint]]]()
  var blobs = newSeq[string]()

  let s = newFileStream(blog)
  if s == nil:
    blogCache = BlogCache(blog: blog)
    return
  defer: s.close()

  var buf = ""

  try:
    while not s.atEnd():
      result[1].add s.stat()
      let sz = s.readUInt32().int
      buf = s.readStr(sz)
      discard s.readUInt32()
      blobs.add(buf)
      let info = infoFromGzip(buf)
      for ifName, netInfo in info.net:
        if ifName.startsWith("veth"):
          continue
        if ifName notin netHistory:
          netHistory[ifName] = (newSeq[uint](), newSeq[uint]())
        netHistory[ifName].inData.add(netInfo.netInDiff)
        netHistory[ifName].outData.add(netInfo.netOutDiff)
      if ii == result[1].len:
        new(result[0])
        result[0][] = info
  except CatchableError:
    result[2] = true

  if ii == -1:
    if result[1].len > 0:
      new(result[0])
      result[0][] = infoFromGzip(buf)
    else:
      result[0] = fullInfo()

  # Populate the single-blog cache for subsequent accesses.
  # Navigating to a different blog file will cause blogCache.blog to differ,
  # triggering a cache miss and full rebuild for the new file.
  blogCache = BlogCache(
    blog: blog,
    stats: result[1],
    netHistory: netHistory,
    blobs: blobs,
    broken: result[2]
  )

proc histNoLive*(ii: int, blog: string): (FullInfoRef, seq[StatV2], bool) =
  var live = newSeq[StatV2]()
  hist(ii, blog, live, false)

proc saveBlog(): string =
  let dir = getCfg().path
  if not dirExists(dir):
    createDir(dir)
  os.joinPath(dir, now().format("yyyy-MM-dd")).addFileExt("blog")

# Compute the next (blog file, snapshot index) pair for historical navigation.
# d < 0 means go backwards in time (key '['), d > 0 means go forwards (key ']').
# b is the current blog filename, hist is the current snapshot position (0 = live),
# and cnt is the number of snapshots in the current blog file (may be 0 in live mode).
# Returns (blog filename, new hist position).
proc moveBlog*(d: int, b: string, hist, cnt: int): (string, int) =
  # Pressing '[' from live mode (hist == 0): navigate backwards in time.
  if d < 0 and hist == 0:
    if cnt > 0:
      # Stats already loaded — we know the snapshot count of the current blog.
      return (b, cnt)
    else:
      # Live mode doesn't populate stats, so cnt == 0. Read the current blog
      # file to find its actual snapshot count. If it has snapshots, jump to
      # the last one (e.g. 00:30) instead of skipping to the previous day's
      # file (e.g. 23:50).
      let actualCnt = histNoLive(-1, b)[1].len
      if actualCnt > 0:
        return (b, actualCnt)
  elif d < 0 and hist > 1:
    return (b, hist-1)
  elif d > 0 and hist > 0 and hist < cnt:
    return (b, hist+1)
  let dir = getCfg().path
  let files = sorted toSeq(walkFiles(os.joinPath(dir, "*.blog")))
  if d == 0 or b == "":
    if files.len > 0:
      return (files[^1], 0)
    else:
      return ("", 0)
  else:
    let idx = files.find(b)
    if d < 0:
      if idx > 0:
        return (files[idx-1], histNoLive(-1, files[idx-1])[1].len)
      else:
        return (b, 1)
    elif d > 0:
      if idx < files.high:
        return (files[idx+1], 1)
      else:
        return (files[^1], 0)
    else:
      doAssert false

proc save*(): FullInfoRef =
  var lastBlog = moveBlog(0, "", 0, 0)[0]
  var (prev, _, broken) = histNoLive(-1, lastBlog)
  if broken:
    echo lastBlog, " is corrupted"
  result = if prev == nil: fullInfo() else: fullInfo(prev)
  let buf = compress(result[].toJson())
  let blog = saveBlog()
  if broken and lastBlog == blog:
    let cName = blog & ".broken"
    echo "moved to ", cName
    moveFile blog, cName
  let file = open(blog, fmAppend)
  defer: file.close()
  if flock(file.getFileHandle, 2 or 4) != 0:
    writeLine(stderr, "cannot open locked: " & blog)
    quit 1
  defer: discard flock(file.getFileHandle, 8)
  let s = newFileStream(file)
  if s == nil:
    raise newException(IOError, "cannot open " & blog)

  s.saveStat result
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

proc printProcesses*(path: string) =
  let s = newFileStream(path)
  if s == nil:
    echo "Cannot open file: ", path
    quit 1
  defer: s.close()

  var buf: string
  echo "timestamp\tpid\tcpu\tmem_rss_kb\tmem_vsize_kb\tmem_pct\tnet_tcp\tnet_udp\tuser\tname\tcmd"
  while not s.atEnd():
    discard s.stat()
    let sz = s.readUInt32().int
    buf = s.readStr(sz)
    discard s.readUInt32()
    let info = infoFromGzip(buf)
    let tsStr = info.sys.datetime.format(TIME_FORMAT)
    for pid, pinfo in info.pidsInfo:
      echo &"{tsStr}\t{pid}\t{pinfo.cpu:.2f}\t{pinfo.rss div 1024}\t{pinfo.vsize div 1024}\t{pinfo.mem:.2f}\t{pinfo.netSocksTcp}\t{pinfo.netSocksUdp}\t{pinfo.user}\t{pinfo.name}\t{pinfo.cmd}"

type
  PartialFullInfo = object
    sys: SysInfo

proc printSummary*(path: string) =
  let s = newFileStream(path)
  if s == nil:
    echo "Cannot open file: ", path
    quit 1
  defer: s.close()

  var entries: seq[tuple[ts: DateTime, prc: int, cpu: float, memTotal: uint, memAvailable: uint, io: uint]] = @[]

  while not s.atEnd():
    let headerSize = s.readUInt32().int
    var stat: StatV2
    var headerRead = false

    if headerSize == sizeof(StatV2):
      if s.readData(stat.addr, sizeof(StatV2)) == sizeof(StatV2):
        headerRead = true
    elif headerSize == STATV2_OLD_SIZE:
      var buf = newSeq[byte](STATV2_OLD_SIZE)
      if s.readData(buf[0].addr, STATV2_OLD_SIZE) == STATV2_OLD_SIZE:
        copyMem(stat.addr, buf[0].addr, STATV2_OLD_SIZE)
        headerRead = true
    elif headerSize == sizeof(StatV1):
      var sv1: StatV1
      if s.readData(sv1.addr, sizeof(StatV1)) == sizeof(StatV1):
        stat = toStatV2(sv1)
        headerRead = true

    if not headerRead:
      # Skip unknown header format
      s.setPosition(s.getPosition + headerSize)
      let dataSize = s.readUInt32().int
      s.setPosition(s.getPosition + dataSize)
      discard s.readUInt32()
      continue

    # Read compressed data
    let dataSize = s.readUInt32().int
    let buf = s.readStr(dataSize)
    discard s.readUInt32()  # Skip trailing size

    # Extract timestamp from compressed data
    try:
      let jsonStr = uncompress(buf)
      let info = jsonStr.fromJson(PartialFullInfo)
      entries.add((
        ts: info.sys.datetime,
        prc: stat.prc,
        cpu: stat.cpu,
        memTotal: stat.memTotal,
        memAvailable: stat.memAvailable,
        io: stat.io
      ))
    except:
      stderr.writeLine "Skipping corrupt record: ", getCurrentExceptionMsg()

  if entries.len == 0:
    echo "No valid data found in blog: ", path
    return

  # Print summary table
  echo "Timestamp               |  Procs | CPU %  | Mem Total | Mem Avail | I/O"
  echo "------------------------+--------+--------+-----------+-----------+--------"
  for e in entries:
    echo &"{e.ts.format(TIME_FORMAT):<24} | {e.prc:>6} | {e.cpu:>6.2f} | {e.memTotal div 1024 div 1024:>9}M | {e.memAvailable div 1024 div 1024:>9}M | {e.io}"


when isMainModule:
  proc print(fName: string) =
    let s = newFileStream(fName)
    if s == nil:
      return
    defer: s.close()

    var buf = ""

    while not s.atEnd():
      let stat = s.stat()
      let sz = s.readUInt32().int
      let buf = s.readStr(sz)
      discard s.readUInt32()
      let info = infoFromGzip(buf)
      echo stat.toJson
      echo info.toJson

  print("/home/u/.cache/ttop/2025-09-13.blog")
