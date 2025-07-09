import ttop/tui
import ttop/blog
import ttop/onoff
import ttop/triggers

import strutils
import os

const NimblePkgVersion {.strdefine.} = "Unknown"

const Help = """
ttop - system monitoring tool with TUI and historical data service

Usage:
  run [optional-param]
Options:
  -h, --help     print this help
  -s, --save     save snapshot
  --on           enable system.timer (or cron) collector every 10 minutes
  --on <number>  enable system.timer (or cron) collector every <number> minutes
  --off          disable collector
  -l <file>      display overall system load from specified .blog file
  -p <file>      display detailed per-process data from specified .blog file
  -v, --version  version number (""" & NimblePkgVersion & """)


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
        smtpSave save()
      of "--on":
        onoff(true)
      of "--off":
        onoff(false)
      of "-v", "--version":
        echo NimblePkgVersion
      else:
        when defined(debug):
          if paramStr(1) == "--colors":
            colors()
        echo Help
        quit 1
    of 2:
      if paramStr(1) == "--on":
        onoff(true, parseUInt(paramStr(2)))
      elif paramStr(1) == "-p":
        printProcesses(paramStr(2))
      elif paramStr(1) == "-l":
        printSummary(paramStr(2))
      else:
        echo Help
        quit 1
    else:
      echo Help
      quit 1
  except CatchableError, Defect:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()
    quit 1

when isMainModule:
  main()

