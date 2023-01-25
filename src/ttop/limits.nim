import procfs

import options
import tables

const memLimit* = 80
const swpLimit* = 50
const rssLimit* = 70
const cpuLimit* = 80
const dskLimit* = 80
const cpuCoreLimit* = 80
const cpuTempLimit* = 80
const ssdTempLimit* = 60

func checkCpuLimit*(c: CpuInfo): bool =
  c.cpu >= cpuLimit

func checkMemLimit*(m: MemInfo): bool =
  memLimit <= (100 * (m.MemTotal - m.MemAvailable)) div m.MemTotal

func checkSwpLimit*(m: MemInfo): bool =
  swpLimit <= (100 * (m.SwapTotal - m.SwapFree)) div m.SwapTotal

func checkCpuTempLimit*(t: Temp): bool =
  if t.cpu.isSome:
    return t.cpu.get >= cpuTempLimit

func checkSsdTempLimit*(t: Temp): bool =
  if t.nvme.isSome:
    return t.cpu.get >= ssdTempLimit

func checkDiskLimit*(d: Disk): bool =
  dskLimit <= (100 * (d.total - d.avail)) div d.total

func checkAnyDiskLimit(dd: OrderedTableRef[string, Disk]): bool =
  for _, d in dd:
    if checkDiskLimit(d):
      return true

func checkAnyLimit*(info: FullInfoRef): bool =
  checkCpuLimit(info.cpu) or checkMemLimit(info.mem) or
  checkSwpLimit(info.mem) or checkAnyDiskLimit(info.disk)

