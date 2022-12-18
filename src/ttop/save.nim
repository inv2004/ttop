import procfs
import marshal
import zippy
import streams
import tables
import times
import os

type StatV1* = object
  prc*: int
  cpu*: float
  mem*: uint
  io*: uint

proc blogPath(mode = fmRead): string =
  let dir = getCacheDir("ttop")
  if mode != fmRead and not dirExists(dir):
    createDir(dir)
  os.joinPath(dir, now().format("yyyy-MM-dd")).addFileExt("blog")

proc saveStat*(s: FileStream, f: FullInfoRef) =
  var io: uint = 0
  for _, disk in f.disk:
    io += disk.ioUsageRead + disk.ioUsageWrite

  var stat = StatV1(
    prc: f.pidsInfo.len,
    cpu: f.cpu.cpu,
    mem: f.mem.MemTotal - f.mem.MemFree,
    io: io
  )

  let sz = sizeof(StatV1)
  s.write sz.uint32
  s.writeData stat.addr, sz

proc stat(s: FileStream): StatV1 =
  let sz = s.readUInt32().int
  let rsz = s.readData(result.addr, sizeof(StatV1))
  doAssert sz == rsz

proc hist*(ii: int, blog: string): (FullInfoRef, seq[StatV1]) =
  if ii == 0:
    result[0] = fullInfo()
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

proc prevBlog*(h: int, blog = "9999-99-99.blog"): (string, int) =
  let dir = getCacheDir("ttop")
  var maxFile = ""
  for f in walkFiles(os.joinPath(dir, "*.blog")):
    if f == blog:
      if maxFile == "":
        maxFile = blog
      break
    elif f > maxFile:
      maxFile = f
  result[0] = maxFile
  if result[0] == blog:
    result[1] = h
  else:
    result[1] = hist(-1, result[0])[1].len

proc nextBlog*(blog: string): (string, int) =
  let dir = getCacheDir("ttop")
  var next = false
  for f in walkFiles(os.joinPath(dir, "*.blog")):
    if f == blog:
      next = true
    elif next:
      return (f, 1)
  return (blog, 0)

proc save*() =
  var (prev, _) = hist(-1, prevBlog(0)[0])
  let info = if prev == nil: fullInfo() else: fullInfo(prev)
  let buf = compress($$info[])
  let path = blogPath(fmAppend)
  let s = newFileStream(path, fmAppend)
  if s == nil:
    raise newException(IOError, "cannot open " & path)
  defer: s.close()
  s.saveStat info
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

when isMainModule:
  var (_, stats) = hist(0)
  for s in stats:
    echo s
