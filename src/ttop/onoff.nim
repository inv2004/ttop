import osproc
import os
import strformat

# const timer = "*-*-* *:*:08"
const timer = "minutely"
const unit = "ttop"
const descr = "ttop service snapshot collector"

const options = {poUsePath, poEchoCmd}

proc onoff*(enable: bool) =
  let app = getAppFilename()

  let cmd =
    if enable:
      &"systemd-run --user --on-calendar='{timer}' --unit='{unit}' --description='{descr}' {app} -s"
    else:
      &"systemctl --user stop '{unit}.timer'"

  let (output, code) = execCmdEx(cmd, options = options)
  echo output
  if code != 0:
    quit code

