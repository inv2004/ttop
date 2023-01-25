import procfs
import limits
import format
import procfs
import config

import strformat
import tables
import times
import std/smtp

proc findMaxDisk(dd: OrderedTableRef[string, Disk]): string =
  var dsk: uint = 0
  for k, d in dd:
    let dVal = (100 * d.avail) div d.total
    if dVal > dsk:
      result = k

proc genText(info: FullInfoRef, alarm: bool): string =
  # var alarm = false
  # if not forceSend:
  #   alarm = checkAnyLimit(info)
  #   if not alarm:
  #     return
  let host = info.sys.hostname
  let cpu = info.cpu.cpu.formatP(true)
  let memStr = formatD(info.mem.MemAvailable, info.mem.MemTotal)

  let alarmStr = if alarm: "❌" else: "✅"

  result = &"""

{info.sys.datetime}

Status: {alarmStr}
Host: {host}
Cpu: {cpu}
Mem: {memStr}
Dsk:
"""
  for k, d in info.disk:
    result.add &"  {k}: {formatD(d.avail, d.total)}\n"

  result.add "\n"


proc smtpSend*(info: FullInfoRef, forceSend = false) =
  initCfg()
  if not forceSend and not checkAnyLimit(info):
    return

  let txt = genText(info, checkAnyLimit(info))
  let cfg = getCfg().smtp
  var msg = createMessage(&"ttop from {info.sys.hostname}",
                          txt,
                          @[cfg.to])
  let smtpConn = newSmtp(useSsl = cfg.ssl, debug = cfg.debug)
  smtpConn.connect(cfg.host, Port cfg.port)
  smtpConn.auth(cfg.user, cfg.pass)
  smtpConn.sendmail(cfg.fr, @[cfg.to], $msg)

proc smtpCheck*() =
  initCfg(true)
  smtpSend(fullInfo(), true)

