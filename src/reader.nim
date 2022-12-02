import scidacio, milcio, pio, filetype, sequtils

type
  Reader* = object
    kind*: FormatKind
    filename*: string
    scidac*: ScidacReader
    milc*: MilcReader
    raw*: pio.Reader

proc newReader*(fn: string, verb=0): Reader =
  var r = pio.newReader(fn)
  var magic: uint32
  let c = r.read(magic)
  let k = fileFormat(magic)
  r.seekTo(0)
  result.kind = k.kind
  result.filename = fn
  case k.kind
  of Lime:
    result.scidac = newScidacReader(r, verb)
  of Milc:
    result.milc = newMilcReader(r, verb)
  else:
    result.raw = r

proc close*(r: var Reader) =
  case r.kind
  of Lime:
    close r.scidac
  of Milc:
    close r.milc
  else:
    close r.raw

# filemd
# recordmd

proc lattice*(r: var Reader): seq[int] =
  case r.kind
  of Lime:
    result = r.scidac.lattice
  of Milc:
    result = r.milc.lattice
  else:
    echo("Error: called 'lattice' on file of unknown kind ", r.filename)
    quit(1)

proc date*(r: var Reader): string =
  case r.kind
  of Lime:
    result = r.scidac.record.date
  of Milc:
    result = r.milc.header.timestamp
  else:
    echo("Error: called 'date' on file of unknown kind ", r.filename)
    quit(1)

proc size*(r: var Reader): int =
  case r.kind
  of Lime:
    result = r.scidac.latvol * r.scidac.record.typesize * r.scidac.record.datacount
  of Milc:
    result = r.milc.lattice.foldl(a*b) * 4 * 18 * 4
  else:
    result = r.raw.size

proc datatype*(r: var Reader): string =
  case r.kind
  of Lime:
    result = r.scidac.record.datatype
  of Milc:
    result = "ColorMatrix"
  else:
    echo("Error: called 'datatype' on file of unknown kind ", r.filename)
    quit(1)

proc precision*(r: var Reader): string =
  case r.kind
  of Lime:
    result = r.scidac.record.precision
  of Milc:
    result = "F"
  else:
    echo("Error: called 'precision' on file of unknown kind ", r.filename)
    quit(1)

#recGet(colors, int)
#recGet(spins, int)

proc typesize*(r: var Reader): int =
  case r.kind
  of Lime:
    result = r.scidac.record.typesize
  of Milc:
    result = 18*4  # single precision
  else:
    echo("Error: called 'typesize' on file of unknown kind ", r.filename)
    quit(1)

proc datacount*(r: var Reader): int =
  case r.kind
  of Lime:
    result = r.scidac.record.datacount
  of Milc:
    result = 4
  else:
    echo("Error: called 'datacount' on file of unknown kind ", r.filename)
    quit(1)

proc read*(r: var Reader, buf: pointer, nbytes: int): int =
  case r.kind
  of Unknown:
    result = r.read(buf, nbytes)
  else:
    echo("Error: called 'read' on file of kind ", r.kind, " ", r.filename)
    quit(1)

proc nextRecord*(r: var Reader) =
  case r.kind
  of Lime:
    nextRecord r.scidac
  else:
    echo("Error: called 'nextRecord' on file of kind ", r.kind, " ", r.filename)
    quit(1)

proc readBinary*(r: var Reader; buf: pointer; sublattice,offsets: seq[int]) =
  case r.kind
  of Lime:
    readBinary(r.scidac, buf, sublattice, offsets)
  of Milc:
    readBinary(r.milc, buf, sublattice, offsets)
  else:
    echo("Error: called 'readBinary' on file of unknown kind ", r.filename)
    quit(1)

proc finishReadBinary*(r: var Reader) =
  case r.kind
  of Lime:
    finishReadBinary(r.scidac)
  of Milc:
    finishReadBinary(r.milc)
  else:
    echo("Error: called 'finishReadBinary' on file of unknown kind ", r.filename)
    quit(1)

proc checksumError*(r: Reader): bool =
  case r.kind
  of Lime:
    checksumError r.scidac
  of Milc:
    checksumError r.milc
  else:
    echo("Error: called 'checksumError' on file of unknown kind ", r.filename)
    quit(1)

when isMainModule:
  import os
  initPio()
  let nargs = paramCount()
  for i in 1..nargs:
    let fn = paramStr(i)
    var r = newReader(fn)
    echo fn, " ", r.kind
    echo "  size: ", r.size
    if r.kind != Unknown:
      let lat = r.lattice
      let nsites = r.lattice.foldl(a*b)
      echo "  date: ", r.date
      echo "  lattice: ", lat
      echo "  datatype: ", r.datatype
      echo "  precision: ", r.precision
      echo "  typesize: ", r.typesize
      echo "  datacount: ", r.datacount
      var buf = alloc(r.size)
      var sublat = lat
      var offs = lat.mapIt(0)
      r.readBinary(buf, sublat, offs)
      r.finishReadBinary
      echo "checksumError: ", r.checksumError
      echo cast[ptr float32](buf)[]
    else:
      discard
    close r
  finiPio()
