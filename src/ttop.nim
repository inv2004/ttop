import ttop/tui
import ttop/blog
import ttop/onoff

import os

const Help = """
Usage:
  run [optional-param]
Options:
  -h, --help     print this cligen-erated help
  -s, --save     save snapshot
  --on           enable system.timer collector
  --off          disable collector
"""

proc main() =
  try:
    case paramCount():
    of 0:
      tui()
    of 1:
      case paramStr(1)
      of "-h", "--help":
        echo Help
      of "-s", "--save":
        save()
      of "--on":
        onoff(true)
      of "--off":
        onoff(false)
      else:
        echo Help
        quit 1
    else:
      echo Help
      quit 1
  except CatchableError:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()
    quit 1

when isMainModule:
  main()

