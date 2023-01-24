import osproc
import os
import strformat
import strutils

const timer = "*:0/10:08"
# const timer = "minutely"
const unit = "ttop"
const descr = "ttop service snapshot collector"

const cron = "*/10 * * * *"

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

proc getServiceDir(): string =
  if isAdmin():
    result = "/usr/lib/systemd/system"
  else:
    result = getConfigDir().joinPath("systemd", "user")
    if not dirExists result:
      createDir result

proc createConfig() =
  let dir = getServiceDir()

  let app = getAppFilename()
  createService(dir.joinPath(&"{unit}.service"), app)
  createTimer(dir.joinPath(&"{unit}.timer"), app)

proc deleteConfig() =
  let dir = getServiceDir()

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
      elif line0 == "inactive":
        return ""
      elif line0.startsWith "no crontab for":
        return ""
  if code != 0:
    raise newException(ValueError, "cmd error code: " & $code)

proc onOffSystemd(enable: bool) =
  let user = if isAdmin(): "" else: " --user"
  if enable:
    if not isAdmin():
      discard cmd(&"systemctl is-active '{unit}.timer'", true)
    createConfig()
    discard cmd &"systemctl{user} daemon-reload"
    discard cmd &"systemctl{user} enable '{unit}.timer'"
    discard cmd &"systemctl{user} start '{unit}.timer'"
    discard cmd "loginctl enable-linger"
  else:
    discard cmd &"systemctl{user} stop '{unit}.timer'"
    discard cmd &"systemctl{user} disable '{unit}.timer'"
    deleteConfig()
    discard cmd &"systemctl{user} daemon-reload"
    discard cmd "loginctl disable-linger"

proc filter(input: string): string =
  for l in input.splitLines(true):
    if unit in l:
      continue
    result.add l

proc onOffCron(enable: bool) =
  let output = cmd("crontab -l", true)
  var input = filter(output)
  if enable:
    let app = getAppFilename()
    input &= &"{cron} {app} -s\n"
    discard cmd("crontab", false, input)
  else:
    if input == "":
      discard cmd "crontab -r"
    else:
      discard cmd("crontab", false, input)
  discard cmd("crontab -l", true)

proc onoff*(enable: bool) =
  let isSysD =
    try:
      discard cmd "systemctl is-active --quiet /"
      true
    except CatchableError:
      false

  if isSysD:
    onOffSystemd(enable)
  else:
    echo "systemd failed, trying crontab"
    onOffCron(enable)

proc createPkgConfig(root: bool) =
  let pkgBin = "/usr/bin/ttop"
  let cfgDir = (if root: "/" else: "") / "usr/lib/systemd/system"
  echo cfgDir
  createDir(cfgDir)
  createService(cfgDir / &"{unit}.service", pkgBin)
  createTimer(cfgDir / &"{unit}.timer", pkgBin)

when isMainModule:
  createPkgConfig(false)

