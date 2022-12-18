import ttop/tui
import ttop/save

import os

proc isSave(): bool =
  if paramCount() >= 1 and paramStr(1) in ["-s", "--save"]:
    true
  elif getAppFilename().extractFilename() == "ttop":
    false
  else:
    false

proc main() =
  try:
    if isSave():
      save()
    else:
      run()
  except:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()

when isMainModule:
  main()
