import endians, bitops
template `*`(s: string): untyped = unsafeaddr s[0]

template swapEndian(x: var int16|uint16) =
  var y = x
  swapEndian16(addr x, addr y)
template swapEndian(x: var int32|uint32) =
  var y = x
  swapEndian32(addr x, addr y)
template swapEndian(x: var int|int64|uint64) =
  var y = x
  swapEndian64(addr x, addr y)
template roundup(x: int, n: int): int =
  let t = x+n-1
  t - (t mod n)

const LimeMagic = 1164413355'u32
const LimeTypeLength = 128

type
  LimeHeader* = object
    magic*: uint32
    version*: uint16
    flags*: uint16
    length*: int
    limetype*: array[LimeTypeLength, char]

template msgBegin*(h: LimeHeader): bool =
  testBit(h.flags, 15)
template msgEnd*(h: LimeHeader): bool =
  testBit(h.flags, 14)
template `msgBegin=`*(h: var LimeHeader, b: bool) =
  if b: setBit(h.flags, 15)
  else: clearBit(h.flags, 15)
template `msgEnd=`*(h: var LimeHeader, b: bool) =
  if b: setBit(h.flags, 14)
  else: clearBit(h.flags, 14)

template limetypeString*(h: LimeHeader): string =
  $cast[cstring](unsafeaddr h.limetype)

proc `$`*(h: LimeHeader): string =
  result  = "LimeHeader:"
  result &= "\n  magic:    " & $h.magic
  result &= "\n  version:  " & $h.version
  #result &= "\n  flags:    " & $h.flags
  result &= "\n  msgbegin: " & $h.msgBegin
  result &= "\n  msgend:   " & $h.msgEnd
  result &= "\n  length:   " & $h.length
  result &= "\n  limetype: " & h.limetypeString
  #echo h.limetype

proc byterev(h: var LimeHeader) =
  swapEndian h.magic
  swapEndian h.version
  swapEndian h.flags
  swapEndian h.length

type
  LimeReader*[R] = ref object
    reader*: R
    recnum*: int
    offset*: int
    atEnd*: bool
    padlen*: int
    byterev*: bool
    header*: LimeHeader

template echo0*(lr: LimeReader, args: varargs[untyped]) =
  mixin echo0
  lr.reader.echo0 args

proc readHeader(lr: var LimeReader) =
  let n = sizeof(LimeHeader)
  let nread = lr.reader.read(addr lr.header, n)
  #echo "readHeader: nread: ", nread, " (", n, ")"
  if nread != n:
    #echo "INFO: readHeader: short read ", nread, " expected ", n
    lr.atEnd = true
    return
  lr.byterev = false
  if lr.header.magic != LimeMagic:
    lr.byterev = true
    byterev(lr.header)
    if lr.header.magic != LimeMagic:
      echo "Lime error: wrong magic: ", lr.header.magic
  lr.recnum += 1
  lr.offset += n
  lr.padlen = roundup(lr.header.length, 8)
  #echo "Record ", $lr.recnum, " ", lr.header

proc newLimeReader*[R](r: R): LimeReader[R] =
  new result
  result.reader = r
  result.recnum = 0
  result.offset = 0
  result.atEnd = false
  readHeader result

proc close*(lr: var LimeReader) =
  close lr.reader

proc nextRecord*(lr: var LimeReader) =
  let o = lr.offset + lr.padlen
  lr.reader.seekTo(o)
  lr.offset = o
  readHeader lr

proc read*(lr: var LimeReader): string =
  mixin read
  let n = lr.padlen
  result = newString(n)
  let nread = lr.reader.read(result)
  if nread != n:
    echo "LimeReader: short read ", nread, " expected ", n
    quit(-1)

type
  LimeWriter*[W] = ref object
    writer*: W
    recnum*: int
    offset*: int
    padlen*: int
    byterev*: bool
    header*: LimeHeader

template echo0*(lw: LimeWriter, args: varargs[untyped]) =
  lw.writer.echo0 args

proc isLittleEndian(): bool =
  type
    intchar {.union.} = object
      i: int
      c: array[8,char]
  var x: intchar
  x.i = 1
  result = (x.c[0] == 1.char)

proc newLimeWriter*[W](w: W): LimeWriter[W] =
  new result
  result.writer = w
  result.recnum = 0
  result.offset = 0
  result.padlen = 0
  result.byterev = isLittleEndian()
  #echo "newLimeWriter: byterev: ", result.byterev

proc close*(lw: var LimeWriter) =
  close lw.writer

proc setHeader*(lw: var LimeWriter; mb,me: bool; length: int; limetype: string) =
  lw.header.magic = LimeMagic
  lw.header.version = 1
  lw.header.flags = 0
  lw.header.msgBegin = mb
  lw.header.msgEnd = me
  lw.header.length = length
  zeroMem(addr lw.header.limetype, LimeTypeLength)
  copymem(addr lw.header.limetype, unsafeaddr limetype[0], limetype.len)

proc writeHeader*(lw: var LimeWriter) =
  let o = lw.offset + lw.padlen
  #echo "writeHeader offset: ", o
  lw.writer.seekTo(o)
  lw.offset = o
  let n = sizeof(LimeHeader)
  if lw.byterev:
    byterev(lw.header)
  let nwrite = lw.writer.write(addr lw.header, n)
  if lw.byterev:
    byterev(lw.header)
  if nwrite != n:
    echo "Lime writeHeader: short write ", nwrite, " expected ", n
    quit(-1)
  lw.recnum += 1
  lw.offset += n
  lw.padlen = roundup(lw.header.length, 8)
  #echo "Record ", $lr.recnum, " ", lr.header

# writes lw.header.length bytes from buf
proc write*(lw: var LimeWriter, buf: pointer) =
  mixin write
  let n = lw.header.length
  let nwrite = lw.writer.write(buf, n)
  if nwrite != n:
    echo "LimeWriter: short write ", nwrite, " expected ", n
    quit(-1)
proc write*(lw: var LimeWriter, s: string) =
  let n = lw.header.length
  if s.len < n:
    echo "Lime: write string length ", s.len, " shorter than record length ", n
    quit(-1)
  if s.len > n:
    echo "Lime: write string length ", s.len, " larger than record length ", n
  lw.write(*s)


proc testRead(r: var any) =
  mixin read
  var lr = newLimeReader(r)
  #while true:
  for i in 0..<10:
    lr.echo0 "Record ", $lr.recnum, " ", lr.header
    if lr.padlen < 512:
    #if lr.header.limetypeString != "ildg-binary-data":
      let n = lr.padlen
      var buf = newString(n)
      discard r.read(buf)
      lr.echo0 buf
    else:
      lr.echo0 "<binary data>"
    nextRecord lr
    if lr.atEnd: break
    lr.echo0 ""
  close lr

proc testWrite(w: var any) =
  var lw = newLimeWriter(w)
  let data1 = "some record data 1"
  lw.setHeader(true, false, data1.len, "record 1")
  writeHeader lw
  lw.write data1
  let data2 = "some record data 2"
  lw.setHeader(false, true, data2.len, "record 2")
  writeHeader lw
  lw.write data2
  close lw

when isMainModule:
  import pio, os
  let nargs = paramCount()
  case nargs
  of 0:
    let fn = "testwriter.lime"
    var w = newWriter(fn)
    w.echo0 "Writing file: ", fn
    testWrite(w)
    w.close()
  of 1:
    let fn = paramStr(1)
    var r = newReader(fn)
    r.echo0 "Reading file: ", fn
    testRead(r)
    r.close()
  else:
    echo "Requires zero or one file argument."
