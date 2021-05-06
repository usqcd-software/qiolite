import strformat, sequtils

type
  Reader* = ref object
    filename*: string
    isOpen*: bool
    fh*: File
  Writer* = ref object
    filename*: string
    isOpen*: bool
    fh*: File

proc open(rd: var Reader) =
  if not rd.isOpen:
    rd.isOpen = open(rd.fh, rd.filename, fmRead)
    if not rd.isOpen:
      echo "open failed"
      quit(-1)

proc newReader*(fn: string): Reader =
  result.new
  result.filename = fn
  result.isOpen = false
  open result

#proc newReader*(fn: cstring, lat: ptr int32, ndim: int32): Reader =
#  var l = newSeq[int](ndim)
#  let lata = cast[ptr UncheckedArray[int32]](lat)
#  for i in 0..<ndim: l[i] = int lata[i]
#  result = newReader($fn, l)

proc close*(rd: var Reader) =
  if rd.isOpen:
    rd.isOpen = false
    close(rd.fh)

proc seekTo*(rd: var Reader, offset: int) =
  setFilePos rd.fh, offset

proc read*(rd: var Reader, buf: pointer, nbytes: int): int =
  if not rd.isOpen:
    echo "ERROR: Reader read: not open"
    quit(-1)
  #echo "reading: ", nbytes
  let nread = rd.fh.readBuffer(buf, nbytes)
  #if nread != nbytes:
  #  echo &"ERROR: bytes read ({nread}) < nbytes ({nbytes})"
  return nread
template read*(rd: var Reader, buf: ptr typed, nbytes: SomeInteger): int =
  rd.read(cast[pointer](buf), int(nbytes))

proc read*(rd: var Reader, val: var SomeNumber): int =
  let buf = addr val
  let nbytes = sizeof(val)
  rd.read(buf, nbytes)

proc read*(rd: var Reader, val: var string): int =
  let buf = addr val[0]
  let nbytes = val.len
  rd.read(buf, nbytes)

proc read*(rd: var Reader; buf: pointer; elemsize: int;
           lattice,hyperlower,hyperupper: seq[int]): int =
  # FIXME
  let nsites = lattice.foldl(a*b)
  let nbytes = nsites * elemsize
  rd.read(buf, nbytes)

## Writer

proc open(wr: var Writer) =
  if not wr.isOpen:
    echo "open filename: ", wr.filename
    wr.isOpen = open(wr.fh, wr.filename, fmWrite)
    if not wr.isOpen:
      echo "open failed"
      quit(-1)

proc newWriter*(fn: string): Writer =
  result.new
  result.filename = fn
  result.isOpen = false
  open result

#proc newWriter*(fn: cstring, lat: ptr int32, ndim: int32): Writer =
#  result.new
#  var l = newSeq[int](ndim)
#  let lata = cast[ptr UncheckedArray[int32]](lat)
#  for i in 0..<ndim: l[i] = int lata[i]
#  newWriter($fn, l)

proc close*(wr: var Writer) =
  if wr.isOpen:
    close(wr.fh)
    wr.isOpen = false

proc seekTo*(wr: var Writer, offset: int) =
  setFilePos wr.fh, offset

proc write*(wr: var Writer, buf: pointer, nbytes: int) =
  if not wr.isOpen:
    echo "ERROR: Writer write: not open"
    quit(-1)
  echo "writing: ", nbytes
  let nwrite = wr.fh.writeBuffer(buf, nbytes)
  if nwrite != nbytes:
    echo &"ERROR: bytes written ({nwrite}) < nbytes ({nbytes})"
template write*(wr: var Writer, buf: ptr typed, nbytes: SomeInteger) =
  wr.write(cast[pointer](buf), int(nbytes))

proc write*(wr: var Writer, val: SomeNumber) =
  let buf = unsafeaddr val
  let nbytes = sizeof(val)
  wr.write(buf, nbytes)

proc write*(wr: var Writer, val: string) =
  let buf = unsafeaddr val[0]
  let nbytes = val.len
  wr.write(buf, nbytes)
