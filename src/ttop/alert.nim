import procfs
import limits
import format
import procfs
import config

import strformat
import tables
import times
import os

const alertFile = "alert.txt"
const infoFile = "info.txt"

proc genText(info: FullInfoRef, alarm: bool): string =
  let host = info.sys.hostname
  let cpuStr = info.cpu.cpu.formatP(true)
  let memStr = formatD(info.mem.MemAvailable, info.mem.MemTotal)
  let alarmStr = if alarm: "❌" else: "✅"

  result = &"""

{info.sys.datetime}

Status: {alarmStr}
Host: {host}
Cpu: {cpuStr}
Mem: {memStr}
Dsk:
"""
  for k, d in info.disk:
    result.add &"  {k}: {formatD(d.avail, d.total)}\n"

  result.add "\n"

proc smtpSave*(info: FullInfoRef) =
  let alarm = checkAnyLimit(info)
  let txt = genText(info, alarm)

  let cfg = getCfg()

  let (fName, fDel) =
    if alarm: (alertFile, infoFile)
    else: (infoFile, alertFile)

  removeFile(cfg.path / fDel)
  writeFile(cfg.path / fName, txt)

