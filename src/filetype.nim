import endians

const MILC_MAGIC_NUMBER = 0x4e87'u32  # 20103
#const MILC_MAGIC_NUMBER_REV = 0x874e0000'u32  # 2270035968
const LimeMagic = 1164413355'u32

type
  FormatKind* = enum
    Lime, Milc, Unknown
  FileFormat* = object
    kind*: FormatKind
    byterev*: bool

proc formatKind*(x: uint32): FormatKind =
  case x
  of MILC_MAGIC_NUMBER: Milc
  of LimeMagic: Lime
  else: Unknown

proc fileFormat*(ui: uint32): FileFormat =
  var k = formatKind(ui)
  #echo ui, " ", k
  result.byterev = false
  if k == Unknown:
    var uir = ui
    swapEndian32(addr uir, unsafeAddr ui)
    #echo ui, " ", uir
    k = formatKind(uir)
    result.byterev = true
  result.kind = k

proc fileFormat*(bytes: pointer): FileFormat =
  var ui = cast[ptr uint32](bytes)[]
  fileFormat(ui)

proc fileFormat*(fn: string): FileFormat =
  let fh = open(fn)
  var buf: uint32
  let c = fh.readBuffer(addr buf, sizeof(buf))
  fh.close
  result = fileFormat(addr buf)

when isMainModule:
  import os
  let nargs = paramCount()
  for i in 1..nargs:
    let fn = paramStr(i)
    let ff = fileFormat(fn)
    echo fn, " ", ff
