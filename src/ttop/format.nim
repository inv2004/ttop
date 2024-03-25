import strformat
import times

proc formatP*(f: float, left = false): string =
  if f >= 100.0:
    fmt"{f:.0f}"
  elif left:
    fmt"{f:<4.1f}"
  else:
    fmt"{f:4.1f}"

proc formatSPair*(b: int): (float, string) =
  const postStr = [" b", "KB", "MB", "GB", "TB", "PB"]

  var x = b * 10
  for i, v in postStr:
    if x < 10240:
      return (x / 10, v)
    x = (x+512) div 1024

  return (b.float, ".")

proc formatN3*(a: int): string =
  if a > 999:
    fmt "{(a div 1000):2}k"
  else:
    fmt "{a:3}"

proc formatS*(a: int): string =
  let (n, s) = formatSPair(a)
  if a < 1024:
    fmt "{n.int} {s}"
  else:
    fmt "{n:.1f} {s}"

proc formatS*(a, b: int, delim = " / "): string =
  let (n1, s1) = formatSPair(a)
  let (n2, s2) = formatSPair(b)
  if s1 == s2:
    if b < 1024:
      fmt "{n1.int}{delim}{n2.int} {s2}"
    else:
      fmt "{n1:.1f}{delim}{n2:.1f} {s2}"
  else:
    if a < 1024 and b < 1024:
      fmt "{n1.int} {s1}{delim}{n2.int} {s2}"
    elif a < 1024:
      fmt "{n1.int} {s1}{delim}{n2:.1f} {s2}"
    else:
      fmt "{n1:.1f} {s1}{delim}{n2.int} {s2}"

proc formatSI*(a, b: int, delim = "/"): string =
  let (n1, s1) = formatSPair(a)
  let (n2, s2) = formatSPair(b)
  if s1 == s2:
    fmt "{n1.int}{delim}{n2.int}{s2[0]}"
  else:
    fmt "{n1.int}{s1[0]}{delim}{n2.int}{s2[0]}"

proc formatS*(a: uint): string =
  formatS(int(a))

proc formatS*(a, b: uint, delim = " / "): string =
  formatS(int(a), int(b), delim)

proc formatD*(a, b: uint, delim = " / "): string =
  formatS(int(b-a), int(b), delim)

proc formatSI*(a, b: uint, delim = "/"): string =
  formatSI(int(a), int(b), delim)

proc formatT*(ts: int): string =
  let d = initDuration(seconds = ts)
  let p = d.toParts()
  fmt"{p[Days]*24 + p[Hours]:2}:{p[Minutes]:02}:{p[Seconds]:02}"

proc formatT*(ts: uint): string =
  formatT(int(ts))

proc formatC*(temp: float64): string =
  fmt"{temp.int}℃"

when isMainModule:
  echo "|", 0.0.formatP, "|"
  echo "|", 5.2.formatP, "|"
  echo "|", 10.5.formatP, "|"
  echo "|", 100.formatP, "|"
  echo "|", 512.formatS, "|"
  echo "|", 1512.formatS, "|"
  echo "|", 8512.formatS, "|"
  echo "|", 80512.formatS, "|"
  echo "|", 2000512.formatS, "|"
  echo "|", formatS(3156216320.uint, 12400328704.uint), "|"
  echo "|", formatS(156216320.uint, 12400328704.uint), "|"
  echo "|", formatS(320.uint, 12400328704.uint), "|"
