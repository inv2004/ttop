import parsecfg
import os
import strutils

const cfgName = "ttop.conf"

const PKGDATA* = "/var/log/ttop"

type
  Smtp* = object
    host*: string
    port*: int
    user*: string
    pass*: string
    fr*: string
    to*: string
    ssl*: bool
    debug*: bool

  CfgRef* = ref object
    path*: string
    smtp*: Smtp

var cfg: CfgRef

proc getDataDir(): string =
  if dirExists PKGDATA:
    return PKGDATA
  else:
    getCacheDir("ttop")

proc loadConfig(): Config =
  try:
    return loadConfig(getConfigDir() / "ttop" / cfgName)
  except IOError:
    try:
      return loadConfig("/etc" / cfgName)
    except IOError:
      discard

proc initCfg*(nonTui = false) =
  let config = loadConfig()

  let portStr = config.getSectionValue("smtp", "port")
  var port = 465
  if portStr != "":
    port = portStr.parseInt

  cfg = CfgRef(
    path: config.getSectionValue("data", "path"),
    smtp: Smtp(
      host: config.getSectionValue("smtp", "host"),
      port: port,
      user: config.getSectionValue("smtp", "user"),
      pass: config.getSectionValue("smtp", "pass"),
      fr: config.getSectionValue("smtp", "from"),
      to: config.getSectionValue("smtp", "to"),
      ssl: config.getSectionValue("smtp", "ssl") == "true",
      debug: config.getSectionValue("smtp", "debug") == "true"
    )
  )

  if cfg.path == "":
    cfg.path = getDataDir()

  if nonTui:
    if cfg.smtp.host != "":
      if cfg.smtp.user == "":
        echo "[stmp].user is not defined"
      if cfg.smtp.pass == "":
        echo "[stmp].pass is not defined"
      if cfg.smtp.fr == "":
        echo "[stmp].from is not defined"
      if cfg.smtp.to == "":
        echo "[stmp].to is not defined"

proc getCfg*(): CfgRef =
  if cfg == nil:
    initCfg()

  cfg

