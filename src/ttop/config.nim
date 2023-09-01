import parsetoml
import os

const cfgName = "ttop.toml"

const PKGDATA* = "/var/log/ttop"
const DOCKER_SOCK* = "/var/run/docker.sock"

type
  Trigger* = object
    onAlert*: bool
    onInfo*: bool
    debug*: bool
    cmd*: string
  CfgRef* = ref object
    path*: string
    docker*: string
    light*: bool
    triggers*: seq[Trigger]

var cfg: CfgRef

proc getDataDir(): string =
  if dirExists PKGDATA:
    return PKGDATA
  else:
    getCacheDir("ttop")

proc loadConfig(): TomlValueRef =
  try:
    return parseFile(getConfigDir() / "ttop" / cfgName)
  except IOError:
    try:
      return parseFile("/etc" / cfgName)
    except IOError:
      discard

proc initCfg*() =
  let toml = loadConfig()

  cfg = CfgRef(
    light: toml{"light"}.getBool(),
    path: toml{"data", "path"}.getStr(getDataDir()),
    docker: toml{"docker"}.getStr(DOCKER_SOCK)
  )

  for t in toml{"trigger"}.getElems():
    let onInfo = t{"on_info"}.getBool()
    let onAlert = t{"on_alert"}.getBool(not onInfo)
    cfg.triggers.add Trigger(
      onAlert: onAlert,
      onInfo: onInfo,
      debug: t{"debug"}.getBool(),
      cmd: t{"cmd"}.getStr()
    )

proc getCfg*(): CfgRef =
  if cfg == nil:
    initCfg()
  cfg

