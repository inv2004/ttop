import parsecfg
import os

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

  let path =
    if config == nil: getDataDir()
    else: config.getSectionValue("data", "path")

  cfg = CfgRef(
    path: path
  )

proc getCfg*(): CfgRef =
  if cfg == nil:
    initCfg()
  cfg

