import ttop/tui
import ttop/blog
import ttop/onoff

import tables

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

proc run(save = false, on = false, off = false) =
  try:
    if on: onoff(true)
    elif off: onoff(false)
    elif save: save()
    else: tui()
  except CatchableError:
    let ex = getCurrentException()
    echo ex.msg
    echo ex.getStackTrace()
    quit 1

const Help = {
    "save": "save snapshot",
    "on": "enable system.timer collector",
    "off": "disable collector"
  }.toTable

const Short = {
    "save": 's',
    "on": '\0',
    "off": '\0'
  }.toTable

when isMainModule:
  import cligen

  dispatch run, help = Help, short = Short

