import osproc
import os
import strformat
import strutils

const timer = "*:0/10:08"
# const timer = "minutely"
const unit = "ttop"
const descr = "ttop service snapshot collector"

const cron = "*/10 * * * * ttop -s"

const options = {poUsePath, poEchoCmd, poStdErrToStdOut}

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

proc createTimer(file: string, app: string) =
  if fileExists file:
    return
  echo "create ", file
  writeFile(file,
      &"""
[Unit]
Description={descr} timer

[Timer]
OnCalendar={timer}

[Install]
WantedBy=timers.target
""")

proc createConfig() =
  let dir = getConfigDir().joinPath("systemd", "user")
  if not dirExists dir:
    createDir dir

  let app = getAppFilename()
  createService(dir.joinPath(&"{unit}.service"), app)
  createTimer(dir.joinPath(&"{unit}.timer"), app)

proc deleteConfig() =
  let dir = getConfigDir().joinPath("systemd", "user")

  var file = dir.joinPath(&"{unit}.service")
  echo "delete ", file
  removeFile file
  file = dir.joinPath(&"{unit}.timer")
  echo "delete ", file
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
      if line0.startsWith "no crontab for":
        return ""
  if code != 0:
    raise newException(ValueError, "cmd error code: " & $code)

proc onOffSystemd(enable: bool) =
  if enable:
    discard cmd(&"systemctl check '{unit}.timer'", true)
    createConfig()
    discard cmd "systemctl --user daemon-reload"
    discard cmd &"systemctl --user start '{unit}.timer'"
    discard cmd "loginctl enable-linger"
  else:
    discard cmd &"systemctl --user stop '{unit}.timer'"
    deleteConfig()
    discard cmd "systemctl --user daemon-reload"
    discard cmd "loginctl disable-linger"

proc filter(input: string): string =
  for l in input.splitLines(true):
    if "ttop" in l:
      continue
    result.add l

proc onOffCron(enable: bool) =
  let output = cmd("crontab -l", true)
  var input = filter(output)
  if enable:
    input &= cron & "\n"
    discard cmd("crontab", false, input)
  else:
    if input == "":
      discard cmd "crontab -r"
    else:
      discard cmd("crontab", false, input)
  discard cmd("crontab -l", true)

proc onoff*(enable: bool) =
  try:
    discard cmd "systemctl is-active --quiet service"
    onOffSystemd(enable)
  except CatchableError:
    echo "systemd failed, trying crontab"
    onOffCron(enable)

proc createPkgConfig() =
  let pkgBin = "/usr/bin/ttop"
  let cfgDir = "usr/lib/systemd/system"
  createDir(cfgDir)
  createService(cfgDir / &"{unit}.service", pkgBin)
  createTimer(cfgDir / &"{unit}.timer", pkgBin)

when isMainModule:
  createPkgConfig()

