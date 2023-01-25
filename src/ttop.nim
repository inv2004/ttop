import ttop/tui
import ttop/blog
import ttop/onoff
import ttop/smtp

import strutils
import os

const Help = """
Usage:
  run [optional-param]
Options:
  -h, --help     print this help
  -s, --save     save snapshot
  --on           enable system.timer (or cron) collector every 10 minutes
  --on <number>  enable system.timer (or cron) collector every <number> minutes
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
        smtpSend save()
      of "--on":
        onoff(true)
      of "--off":
        onoff(false)
      else:
        echo Help
        quit 1
    of 2:
      if paramStr(1) == "--on":
        onoff(true, parseUInt(paramStr(2)))
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

