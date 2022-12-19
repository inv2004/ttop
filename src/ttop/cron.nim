import osproc
import os
import strutils
import sequtils

proc cronSwitch*(enable: bool) =
  let options = {poUsePath, poEchoCmd}
  var (output, code) = execCmdEx("crontab -l", options = options)
  if code notin [0, 1]:
    quit 1
  var cron = ""
  var found = false
  for line in output.split(Newlines):
    if "ttop -s" in line:
      found = true
      if cron == "\n" or cron.endsWith("\n\n"):
        cron = cron[0..^2]
      continue
    cron.add line&"\n"

  if enable and found:
    return
  if not enable and not found:
    return

  echo "update crontab"

  if enable:
    cron.add "*/8 * * * * " & getAppFilename() & " -s\n"

  echo "cron: ", cron.len

  (output, code) = execCmdEx("crontab -", options = options,
      input = cron)
  if output.len > 0:
    echo output
  quit code

