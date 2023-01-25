import procfs

const memLimit* = 80
const swpLimit* = 50
const rssLimit* = 70
const cpuLimit* = 80
const cpuCoreLimit* = 80
const cpuTempLimit* = 80
const ssdTempLimit* = 60

proc checkLimits*(fi: FullInfoRef): bool =
  fi.cpu.cpu > cpuLimit

