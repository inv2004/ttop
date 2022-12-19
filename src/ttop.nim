import ttop/tui
import ttop/save
import ttop/cron

import os

proc isSave(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-s", "--save"]:
    true
  else:
    false

proc isEnable(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-enable", "--enable"]:
    true
  else:
    false

proc isDisable(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-disable", "--disable"]:
    true
  else:
    false

proc main() =
  try:
    if isEnable():
      cronSwitch(true)
    elif isDisable():
      cronSwitch(false)
    elif isSave():
      save()
    else:
      run()
  except:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()

when isMainModule:
  main()
