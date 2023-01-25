import parsecfg
import os

const cfgName = "ttop.conf"

const PKGDATA* = "/var/log/ttop"

type
  Smtp* = object
    user*: string
    pass*: string

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

proc getCfg*(): CfgRef =
  if cfg == nil:
    let config = loadConfig()

    cfg = CfgRef(
      path: config.getSectionValue("data", "path"),
      smtp: Smtp(
        user: config.getSectionValue("smtp", "user"),
        pass: config.getSectionValue("smtp", "pass")
      )
    )

    if cfg.path == "":
      cfg.path = getDataDir()

  return cfg

