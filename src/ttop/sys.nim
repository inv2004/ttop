from posix import sysconf, SC_PAGESIZE, SC_CLK_TCK

type
  Fsblkcnt* {.importc: "fsblkcnt_t", header: "<sys/types.h>".} = culong
  Fsfilcnt* {.importc: "fsfilcnt_t", header: "<sys/types.h>".} = culong

  Statvfs* {.importc: "struct statvfs", header: "<sys/statvfs.h>",
            final, pure.} = object ## struct statvfs
    f_bsize*: culong        ## File system block size.
    f_frsize*: culong       ## Fundamental file system block size.
    f_blocks*: Fsblkcnt  ## Total number of blocks on file system
                          ## in units of f_frsize.
    f_bfree*: Fsblkcnt   ## Total number of free blocks.
    f_bavail*: Fsblkcnt  ## Number of free blocks available to
                          ## non-privileged process.
    f_files*: Fsfilcnt   ## Total number of file serial numbers.
    f_ffree*: Fsfilcnt   ## Total number of free file serial numbers.
    f_favail*: Fsfilcnt  ## Number of file serial numbers available to
                          ## non-privileged process.
    f_fsid*: culong         ## File system ID.
    f_flag*: culong         ## Bit mask of f_flag values.
    f_namemax*: culong      ## Maximum filename length.
    # f_spare: array[6, cint]

let hz* = sysconf(SC_CLK_TCK)
var pageSize* = uint sysconf(SC_PAGESIZE)

proc statvfs*(a1: cstring, a2: var Statvfs): cint {.
  importc, header: "<sys/statvfs.h>".}
