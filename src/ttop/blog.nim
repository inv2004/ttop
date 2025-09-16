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

  StatV2(
    prc: f.pidsInfo.len,
    cpu: f.cpu.cpu,
    memTotal: f.mem.MemTotal,
    memAvailable: f.mem.MemAvailable,
    io: io
  )

proc saveStat*(s: FileStream, f: FullInfoRef) =
  var stat = genStat(f)

  let sz = sizeof(StatV2)
  s.write sz.uint32
  s.writeData stat.addr, sz

proc stat(s: FileStream): StatV2 =
  let sz = s.readUInt32().int
  var rsz: int
  case sz
  of sizeof(StatV2):
    rsz = s.readData(result.addr, sizeof(StatV2))
    doAssert sz == rsz
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

proc hist*(ii: int, blog: string, live: var seq[StatV2], forceLive: bool): (FullInfoRef, seq[StatV2]) =
  let fi = fullInfo()
  if ii == 0 or forceLive:
    result[0] = fi
  live.add genStat(fi)

  live.delete((0..live.high - 1000))

  let s = newFileStream(blog)
  if s == nil:
    return
  defer: s.close()

  var buf = ""

  while not s.atEnd():
    result[1].add s.stat()
    let sz = s.readUInt32().int
    buf = s.readStr(sz)
    discard s.readUInt32()
    if not forceLive and ii == result[1].len:
      new(result[0])
      result[0][] = infoFromGzip(buf)

  if ii == -1:
    if result[1].len > 0:
      new(result[0])
      result[0][] = infoFromGzip(buf)

    else:
      result[0] = fullInfo()

proc histNoLive*(ii: int, blog: string): (FullInfoRef, seq[StatV2]) =
  var live = newSeq[StatV2]()
  hist(ii, blog, live, false)

proc saveBlog(): string =
  let dir = getCfg().path
  if not dirExists(dir):
    createDir(dir)
  os.joinPath(dir, now().format("yyyy-MM-dd")).addFileExt("blog")

proc moveBlog*(d: int, b: string, hist, cnt: int): (string, int) =
  if d < 0 and hist == 0 and cnt > 0:
    return (b, cnt)
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
  var (prev, _) = histNoLive(-1, lastBlog)
  result = if prev == nil: fullInfo() else: fullInfo(prev)
  let buf = compress(result[].toJson())
  let blog = saveBlog()
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
