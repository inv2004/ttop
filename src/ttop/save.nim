import procfs
import marshal
import zippy
import streams

const blog = "/tmp/1.blog"

proc hist*(ii: int): (FullInfoRef, int) =
  let s = newFileStream(blog)
  if s == nil:
    return (nil, 0)
  defer: s.close()
  if ii == 0:
    result[0] = fullInfo()

  var buf = ""

  result[1] = 0
  while not s.atEnd():
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
  var (prevInfo, _) = hist(-1)
  echo prevInfo.repr
  let info = if prevInfo == nil: fullInfo() else: fullInfo(prevInfo)
  let buf = compress($$info[])
  let s = newFileStream(blog, fmAppend)
  defer: s.close()
  s.write buf.len.uint32
  s.write buf
  s.write buf.len.uint32

when isMainModule:
  echo hist(4)
