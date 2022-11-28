import procfs
import marshal
import zippy
import streams

const blog = "/tmp/1.blog"

proc save*() =
  let info = fullInfo()
  let buf = compress($$info[])
  let s = newFileStream(blog, fmAppend)
  defer: s.close()
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

proc hist*(ii: int): (FullInfoRef, int) =
  let s = newFileStream(blog)
  defer: s.close()
  if ii == 0:
    result[0] = fullInfo()

  result[1] = 0
  while not s.atEnd():
    let sz = s.readUInt32().int
    let buf = s.readStr(sz)
    discard s.readUInt32()
    if ii == result[1]+1:
      new(result[0])
      result[0][] = to[FullInfo](uncompress(buf))
    inc result[1]

when isMainModule:
  echo hist(4)
