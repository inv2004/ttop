import ttop/tui
import ttop/blog
import ttop/onoff

import os

proc isSave(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-s", "--save"]:
    true
  else:
    false

proc isEnable(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-on", "--on"]:
    true
  else:
    false

proc isDisable(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-off", "--off"]:
    true
  else:
    false

proc main() =
  try:
    if isEnable():
      onoff(true)
    elif isDisable():
      onoff(false)
    elif isSave():
      save()
    else:
      run()
  except:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()
    quit 1

when isMainModule:
  main()
