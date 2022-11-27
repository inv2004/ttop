import ttop/tui
import ttop/save

import os

proc isSave(): bool =
  if paramCount() >= 1 and paramStr(1) == "-s":
    true
  elif getAppFilename().extractFilename() == "ttop":
    false
  else:
    false

proc main() =
  if isSave():
    save()
  else:
    run()

when isMainModule:
  main()
