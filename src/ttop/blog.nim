import procfs
import marshal
import zippy
import streams
import tables
import times
import os
import sequtils
import algorithm

type StatV1* = object
  prc*: int
  cpu*: float
  mem*: uint
  io*: uint

const PKGDATA = "/var/log/ttop"

proc flock(fd: FileHandle, op: int): int {.header: "<sys/file.h>",
    importc: "flock".}

proc genStat(f: FullInfoRef): StatV1 =
  var io: uint = 0
  for _, disk in f.disk:
    io += disk.ioUsageRead + disk.ioUsageWrite

  StatV1(
    prc: f.pidsInfo.len,
    cpu: f.cpu.cpu,
    mem: f.mem.MemTotal - f.mem.MemFree,
    io: io
  )

proc saveStat*(s: FileStream, f: FullInfoRef) =
  var stat = genStat(f)

  let sz = sizeof(StatV1)
  s.write sz.uint32
  s.writeData stat.addr, sz

proc stat(s: FileStream): StatV1 =
  let sz = s.readUInt32().int
  let rsz = s.readData(result.addr, sizeof(StatV1))
  doAssert sz == rsz

proc hist*(ii: int, blog: string, live: var seq[StatV1]): (FullInfoRef, seq[StatV1]) =
  if ii == 0:
    result[0] = fullInfo()
    live.add genStat result[0]
  else:
    live.add genStat(fullInfo())

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
    if ii == result[1].len:
      new(result[0])
      result[0][] = to[FullInfo](uncompress(buf))

  if ii == -1:
    if result[1].len > 0:
      new(result[0])
      result[0][] = to[FullInfo](uncompress(buf))
    else:
      result[0] = fullInfo()

proc histNoLive*(ii: int, blog: string): (FullInfoRef, seq[StatV1]) =
  var live = newSeq[StatV1]()
  hist(ii, blog, live)

proc getDataDir(): string =
  if dirExists PKGDATA:
    return PKGDATA
  else:
    getCacheDir("ttop")

proc saveBlog(): string =
  let dir = getDataDir()
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
  let dir = getDataDir()
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

proc save*() =
  var lastBlog = moveBlog(0, "", 0, 0)[0]
  var (prev, _) = histNoLive(-1, lastBlog)
  let info = if prev == nil: fullInfo() else: fullInfo(prev)
  let buf = compress($$info[])
  let blog = saveBlog()
  let file = open(blog, fmAppend)
  if flock(file.getFileHandle, 2 or 4) != 0:
    writeLine(stderr, "cannot open locked: " & blog)
    quit 1
  defer: discard flock(file.getFileHandle, 8)
  let s = newFileStream(file)
  if s == nil:
    raise newException(IOError, "cannot open " & blog)
  defer: s.close()
  s.saveStat info
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

when isMainModule:
  var lastBlog = moveBlog(0, "", 0, 0)[0]
  var (prev, _) = hist(-1, lastBlog)
  let info = if prev == nil: fullInfo() else: fullInfo(prev)
  info.pidsInfo.clear()
  info.cpus.setLen 0
  # info.disk.clear()
  echo prev.disk["nvme0n1p5"].ioWrite
  echo info.disk["nvme0n1p5"].ioWrite
  echo info.disk["nvme0n1p5"].ioUsageWrite
  echo info[]
  let buf = compress($$info[])

