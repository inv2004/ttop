import procfs
import marshal
import zippy
import streams
import tables

type StatV1* = object
  prc*: int
  cpu*: float
  mem*: uint
  io*: uint

const blog = "/tmp/1.blog"

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

proc hist*(ii: int): (FullInfoRef, int, seq[StatV1]) =
  if ii == 0:
    result[0] = fullInfo()
  let s = newFileStream(blog)
  if s == nil:
    return
  defer: s.close()

  var buf = ""

  result[1] = 0
  while not s.atEnd():
    result[2].add s.stat()
    let sz = s.readUInt32().int
    buf = s.readStr(sz)
    discard s.readUInt32()
    if ii == result[1]+1:
      new(result[0])
      result[0][] = to[FullInfo](uncompress(buf))
    inc result[1]

  if ii == -1:
    if result[1] > 0:
      new(result[0])
      result[0][] = to[FullInfo](uncompress(buf))
    else:
      result[0] = fullInfo()

proc save*() =
  var (prev, _, _) = hist(-1)
  let info = if prev == nil: fullInfo() else: fullInfo(prev)
  let buf = compress($$info[])
  let s = newFileStream(blog, fmAppend)
  defer: s.close()
  s.saveStat info
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

when isMainModule:
  var (info, _, stats) = hist(0)
  for s in stats:
    echo s
