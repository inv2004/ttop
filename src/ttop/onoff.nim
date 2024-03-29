from config import PKGDATA, DOCKER_SOCK

import osproc
import os
import strformat
import strutils

const unit = "ttop"
const descr = "ttop service snapshot collector"

const options = {poUsePath, poEchoCmd, poStdErrToStdOut}

proc createToml(file: string) =
  if fileExists file:
    return
  echo "create ", file
  writeFile(file,
      """
# light = false
# docker = """" & DOCKER_SOCK & """"   # custom docker socket path

# [data]
# path = "/var/log/ttop"   # custom storage path (default = if exists /var/log/ttop, else ~/.cache/ttop )

# [[trigger]]              # telegram example
# on_alert = true          # execute trigger on alert (true if no other on_* provided)
# on_info = true           # execute trigger on without alert (default = false)
# debug = false            # output stdout/err from cmd (default = false)
# cmd = '''
# read -d '' TEXT
# curl -X POST \
#   -H 'Content-Type: application/json' \
#   -d "{\"chat_id\": $CHAT_ID, \"text\": \"$TEXT\", \"disable_notification\": $TTOP_INFO}" \
#   https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage
# '''

# # cmd receives text from stdin. The following env vars are set:
# #   TTOP_ALERT (true|false) - if alert
# #   TTOP_INFO  (true|false) - opposite to alert
# #   TTOP_TYPE  (alert|info) - trigger type
# #   TTOP_HOST               - host name
# # you can find your CHAT_ID by send smth to your bot and run:
# #    curl https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getUpdates

# [[trigger]]               # smtp example
# cmd = '''
# read -d '' TEXT
# TEXT="Subject: ttop $TTOP_TYPE from $TTOP_HOST
#
# $TEXT"
# echo "$TEXT" | curl --ssl-reqd \
#   --url 'smtps://smtp.gmail.com:465' \
#   --user 'login:password' \
#   --mail-from 'from@gmail.com' \
#   --mail-rcpt 'to@gmail.com' \
#   --upload-file -
# '''

""")

proc createService(file: string, app: string) =
  if fileExists file:
    return
  echo "create ", file
  writeFile(file,
      &"""
[Unit]
Description={descr}

[Service]
ExecStart={app} -s

[Install]
WantedBy=ttop.timer
""")

proc createTimer(file: string, app: string, interval: uint) =
  if fileExists file:
    return
  echo "create ", file
  writeFile(file,
      &"""
[Unit]
Description={descr} timer

[Timer]
OnCalendar=*:0/{interval}:08

[Install]
WantedBy=timers.target
""")

proc getServiceDir(pkg: bool): string =
  if pkg:
    result = "usr/lib/systemd/system"
    createDir result
  elif isAdmin():
    result = "/usr/lib/systemd/system"
  else:
    result = getConfigDir().joinPath("systemd", "user")
    if not dirExists result:
      echo "create ", result
      createDir result

proc createConfig(pkg: bool, interval: uint) =
  let app = if pkg: "/usr/bin/ttop" else: getAppFilename()
  let dir = getServiceDir(pkg)

  createService(dir.joinPath(&"{unit}.service"), app)
  createTimer(dir.joinPath(&"{unit}.timer"), app, interval)

  if pkg:
    createDir "etc"
    createToml("etc/ttop.toml")

proc deleteConfig() =
  let dir = getServiceDir(false)

  var file = dir.joinPath(&"{unit}.service")
  echo "rm ", file
  removeFile file
  file = dir.joinPath(&"{unit}.timer")
  echo "rm ", file
  removeFile file

proc cmd(cmd: string, check = false, input = ""): string =
  var code: int
  (result, code) = execCmdEx(cmd, options = options, input = input)
  if result.len > 0:
    echo result
    if check:
      let line0 = result.splitLines()[0]
      if line0 == "active":
        let msg = "Looks like ttop.timer is already running system-wide"
        raise newException(ValueError, "cmd error: " & msg)
      elif line0 == "inactive":
        return ""
      elif line0.startsWith "no crontab for":
        return ""
  if code != 0:
    raise newException(ValueError, "cmd error code: " & $code)

proc onOffSystemd(enable: bool, interval: uint) =
  if isAdmin():
    echo "WARNING: setup via ROOT"
  let user = if isAdmin(): "" else: " --user"
  if enable:
    if not isAdmin():
      discard cmd(&"systemctl is-active '{unit}.timer'", true)
    createConfig(false, interval)
    discard cmd &"systemctl{user} daemon-reload"
    discard cmd &"systemctl{user} enable --now '{unit}.timer'"
    if not isAdmin():
      discard cmd "loginctl enable-linger"
    if isAdmin():
      echo "mkdir ", PKGDATA
      createDir(PKGDATA)
    discard cmd &"systemctl{user} start '{unit}.service'"
  else:
    discard cmd &"systemctl{user} stop '{unit}.timer'"
    discard cmd &"systemctl{user} disable --now '{unit}.timer'"
    deleteConfig()
    discard cmd &"systemctl{user} daemon-reload"
    if not isAdmin():
      discard cmd "loginctl disable-linger"
    if isAdmin():
      echo "rmdir ", PKGDATA
      for k, p in walkDir(PKGDATA):
        echo "WARN: ", PKGDATA, " is not empty"
        return
      removeDir(PKGDATA)

proc filter(input: string): string =
  for l in input.splitLines(true):
    if unit in l:
      continue
    result.add l

proc onOffCron(enable: bool, interval: uint) =
  let output = cmd("crontab -l", true)
  var input = filter(output)
  let app = getAppFilename()
  if enable:
    input &= &"*/{interval} * * * * {app} -s\n"
    discard cmd("crontab", false, input)
  else:
    if input == "":
      discard cmd "crontab -r"
    else:
      discard cmd("crontab", false, input)
  discard cmd("crontab -l", true)
  if enable:
    discard cmd &"{app} -s"

proc onoff*(enable: bool, interval: uint = 10) =
  let isSysD =
    try:
      discard cmd "systemctl is-active --quiet /"
      true
    except CatchableError, Defect:
      false

  if isSysD:
    onOffSystemd(enable, interval)
  else:
    echo "systemd failed, trying crontab"
    onOffCron(enable, interval)

when isMainModule:
  createConfig(true, 10)
