import procfs
import marshal
import zippy
import streams

const blog = "/tmp/1.blog"

proc count*(): int =
  let s = newFileStream(blog, fmRead)
  if s == nil:
    return
  while not s.atEnd():
    let sz = s.readUInt32()
    discard s.readStr(int(sz))
    discard s.readUInt32()
    inc result

proc save*() =
  let info = fullInfo()
  let buf = compress($$info)
  let s = newFileStream(blog, fmAppend)
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32
  s.close()

proc hist*(ii: int): FullInfo =
  let f = open(blog, fmRead)
  defer: f.close()
  let s = newFileStream(f)
  s.setPosition(f.getFileSize().int)
  for i in 1..ii:
    if s.getPosition() - 4 < 0:
      return
    s.setPosition(s.getPosition().int - 4)
    let sz = s.readUInt32.int
    s.setPosition(s.getPosition().int - 8 - sz)

  let sz = s.readUInt32.int
  let buf = s.readStr(sz)
  to[FullInfo](uncompress(buf))

when isMainModule:
  echo count()
  echo hist(6)
