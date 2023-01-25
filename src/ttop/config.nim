import parsecfg
import os
import strutils

const cfgName = "ttop.conf"

const PKGDATA* = "/var/log/ttop"

type
  CfgRef* = ref object
    path*: string

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

proc initCfg*() =
  let config = loadConfig()

  cfg = CfgRef(
    path: config.getSectionValue("data", "path"),
  )

  if cfg.path == "":
    cfg.path = getDataDir()

proc getCfg*(): CfgRef =
  if cfg == nil:
    initCfg()
  cfg

