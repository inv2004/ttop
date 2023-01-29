import procfs
import limits
import format
import config

import strformat
import tables
import times
import osproc
import streams
import strtabs
import os

const defaultTimeout = initDuration(seconds = 5)

proc genText(info: FullInfoRef, alarm: bool): (string, string) =
  let host = info.sys.hostname
  let cpuStr = info.cpu.cpu.formatP(true)
  let memStr = formatD(info.mem.MemAvailable, info.mem.MemTotal)
  let alarmStr = if alarm: "❌" else: "✅"

  result[0] = &"""

Status: {alarmStr}
Host: {host}
Cpu: {cpuStr}
Mem: {memStr}
Dsk:
"""
  for k, d in info.disk:
    result[0].add &"  {k}: {formatD(d.avail, d.total)}\n"

  # result[0].add &"\n{info.sys.datetime}\n"

  if alarm:
    result[1] = &"Alarm ttop from {host}"
  else:
    result[1] = &"ttop from {host}"

proc exec(cmd: string, body, subj, host: string, alert, debug: bool) =
  if debug:
    echo "CMD: ", cmd

  let env = newStringTable()
  env["TTOP_ALERT"] = $alert
  env["TTOP_INFO"] = $(not alert)
  env["TTOP_TEXT"] = body
  env["TTOP_TYPE"] = if alert: "alert" else: "info"
  env["TTOP_HOST"] = host
  for k, v in envPairs():
    env[k] = v

  var p = startProcess(cmd, env = env, options = {poEvalCommand,
      poStdErrToStdOut})
  let output = p.outputStream()
  let input = p.inputStream()

  input.write(body)
  input.close()

  var line = ""
  var code = -1
  let start = now()
  while true:
    if output.readLine(line):
      if debug:
        echo "> ", line
    else:
      code = peekExitCode(p)
      if code != -1:
        if debug:
          echo "CODE: ", code
        break
    if now() - start > defaultTimeout:
      if debug:
        echo "TIMEOUT"
      terminate(p)
      break
  close(p)

proc smtpSave*(info: FullInfoRef) =
  let alarm = checkAnyLimit(info)
  let (body, subj) = genText(info, alarm)
  let host = info.sys.hostname

  let cfg = getCfg()

  for t in cfg.triggers:
    if (alarm and t.onAlert) or t.onInfo:
      exec(t.cmd, body, subj, host, alarm, t.debug)

