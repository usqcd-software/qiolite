import pio, crc32
import strutils, sequtils, bitops, endians, strformat, times, std/monotimes
export pio

proc byterev32(buf: pointer, nbytes: int) =
  let n = nbytes div 4
  var b = cast[ptr UncheckedArray[uint32]](buf)
  for i in 0..<n:
    var x = b[i]
    swapEndian32(addr b[i], addr x)

proc byterev64(buf: pointer, nbytes: int) =
  let n = nbytes div 8
  var b = cast[ptr UncheckedArray[uint64]](buf)
  for i in 0..<n:
    var x = b[i]
    swapEndian64(addr b[i], addr x)

template byterev(x: var int32|uint32) =
  byterev32(addr x, sizeof(x))
template byterev(x: var int64|uint64) =
  byterev64(addr x, sizeof(x))
template byterev[N:static[int]](x: var array[N,int32|uint32]) =
  byterev32(addr x, 4*N)
template byterev[N:static[int]](x: var array[N,int64|uint64]) =
  byterev64(addr x, 8*N)

template `+`(x: pointer, i: SomeInteger): untyped =
  cast[pointer](cast[ByteAddress](x) + ByteAddress(i))
proc `$`(dur: Duration): string =
  let sec = 1e-6*dur.inMicroseconds.float
  result = sec.formatFloat(ffDecimal, 6)

const MILC_MAGIC_NUMBER = 0x4e87'u32  # 20103
const MILC_MAGIC_NUMBER_REV = 0x874e0000'u32  # 2270035968

type
  MilcChecksum* = object
    sum29: uint32
    sum31: uint32

proc init(x: var MilcChecksum) =
  x.sum29 = 0
  x.sum31 = 0

proc `+`(x,y: MilcChecksum): MilcChecksum =
  result.sum29 = x.sum29 xor y.sum29
  result.sum31 = x.sum31 xor y.sum31

proc `+=`(x: var MilcChecksum, y: MilcChecksum) =
  x = x + y

proc `$`(x: MilcChecksum): string =
  result = "(sum29: 0x" & toHex(x.sum29).toLower & ", sum31: 0x" & toHex(x.sum31).toLower & ")"


type
  MilcHeader* = object
    magicNumber*: uint32  # Identifies file format
    dims*: array[4,int32]  # Full lattice dimensions
    timeStampChars*: array[64,char]  # Date and time stamp
    order*: int32  # 0: no coordinate list attached, values in coordinate order
                   # Nonzero: coordinate list attached, specifying the order
    checksum*: MilcChecksum

proc timestamp*(x: MilcHeader): string =
  result = join(x.timeStampChars)

proc `$`*(x: MilcHeader): string =
  result = "Dims: " & $x.dims & "\n"
  result &= "Timestamp: " & x.timestamp
  #for c in x.timeStampChars:
  #  if c == '\0': break
  #  result &= c
  #result &= "\n"
  #result &= "Checksum: " & $x.checksum

proc initMilcHeader*(x: var MilcHeader, dims: openarray[SomeInteger],
                     timestamp: string = "") =
  var ts = timestamp
  if ts == "":
    let t = getTime().local
    ts = format(t , "ddd MMM dd HH:mm:ss yyyy")
  x.magicNumber = MILC_MAGIC_NUMBER
  for i in 0..<min(4,dims.len):
    x.dims[i] = dims[i]
  for i in 0..<min(64,ts.len):
    x.timestampChars[i] = ts[i]
  x.order = 0
proc initMilcHeader*(x: var MilcHeader, dims: openarray[SomeInteger]) =
  initMilcHeader(x, dims, nil)

proc byterev*(x: var MilcHeader) =
  byterev x.magicNumber
  byterev x.dims
  byterev x.order
  byterev x.checksum.sum29
  byterev x.checksum.sum31

# returns true if byte reversal was needed
proc read*(x: var MilcHeader, r: var Reader): bool =
  let c = r.read(x)
  if c != sizeof(MilcHeader):
    r.echo0 "Error: header read short ", c, " expected ", sizeof(MilcHeader)
    quit(-1)
  if x.magicNumber != MILC_MAGIC_NUMBER:
    if x.magicNumber != MILC_MAGIC_NUMBER_REV:
      echo "Error: MILC wrong magic number in header ", x.magicNumber
      quit(-1)
    result = true
    x.byterev
  if x.order != 0:
    echo "Error: unsupporter order ", x.order
    quit(-1)

proc getMilcChecksum*(x: ptr UncheckedArray[uint32], n: int, offset=0): MilcChecksum =
  template `^=`(x,y: untyped) = x = x xor y
  #echo "N: ", n, " ", n div (4*18)
  for i in 0..<n:
    let t = x[i]
    let k = offset + i
    let k29 = k mod 29
    let k31 = k mod 31
    result.sum29 ^= (t shl k29) or (t shr (32-k29))
    result.sum31 ^= (t shl k31) or (t shr (32-k31))
template getMilcChecksum*[T](x: openArray[T], offset=0): MilcChecksum =
  let n = (x.len*sizeof(x[0])) div sizeof(uint32)
  getMilcChecksum(cast[ptr carray[uint32]](addr x[0]), n, offset)
template getMilcChecksum*(x: pointer, n: int, offset=0): MilcChecksum =
  getMilcChecksum(cast[ptr UncheckedArray[uint32]](x), n, offset)

type
  MilcReader* = ref object
    verbosity*: int
    r*: Reader
    header*: MilcHeader
    byterev*: bool
    lattice*: seq[int]
    localChecksum*: MilcChecksum
    checksum*: MilcChecksum

template echo0*(mr: MilcReader, args: varargs[untyped]) =
  mr.r.echo0 args

template checksumError*(mr: MilcReader): bool =
  mr.localChecksum != mr.checksum

proc newMilcReader*(r: var Reader, verb=0): MilcReader =
  new result
  result.verbosity = verb
  result.r = r
  result.byterev = result.header.read(r)
  result.lattice.newSeq(4)
  for i in 0..3: result.lattice[i] = result.header.dims[i]
  init result.localChecksum
  init result.checksum

proc newMilcReader*(fn: string, verb=0): MilcReader =
  var r = newReader(fn)
  newMilcReader(r, verb)

proc close*(mr: var MilcReader) =
  mr.r.close

proc checksumHyper(buf: pointer; elemsize: int;
                   lattice,sublattice,offsets: seq[int]): MilcChecksum =
  let elems = elemsize div 4
  let nd = lattice.len
  var x = newSeq[int](nd)
  var dlex = newSeq[int](nd)
  var dl = 1
  var nsites = 1
  var lex = 0
  for i in 0..<nd:
    x[i] = 0
    dlex[i] = dl
    lex += dl * offsets[i]
    dl *= lattice[i]
    nsites *= sublattice[i]
  var s: MilcChecksum
  s.init
  for i in 0..<nsites:
    let t = getMilcChecksum(buf+i*elemsize, elems, lex*elems)
    s += t
    var j = 0
    while j < nd:
      x[j] += 1
      lex += dlex[j]
      if x[j] < sublattice[j]:
        break
      x[j] = 0
      lex -= dlex[j] * sublattice[j]
      j += 1
  result = s
  #result = getMilcChecksum(buf, nsites*elems, 0)

proc readBinary*(mr: var MilcReader; buf: pointer; sublattice,offsets: seq[int]) =
  let t0 = getMonoTime()
  let sitebytes = 4 * 18 * 4  # single precision
  var nsites = sublattice.foldl(a*b)
  mr.r.seekTo(sizeof(MilcHeader))
  let nread = mr.r.read(buf, sitebytes, mr.lattice, sublattice, offsets)
  if nread != nsites*sitebytes:
    echo "Error: readBinary short read ", nread, " expected ", nsites*sitebytes
    quit(-1)
  let t1 = getMonoTime()
  if mr.byterev:
    byterev32(buf, nread)
  let chksum = checksumHyper(buf, sitebytes, mr.lattice, sublattice, offsets)
  #echo "localChecksum: ", chksum
  mr.localChecksum += chksum
  #mr.r.seekTo(sizeof(MilcHeader)+nread)
  #let c = mr.r.read(mr.checksum)
  mr.checksum = mr.header.checksum

  #[
  let t2 = getMonoTime()
  if sr.lr.byterev:
    if sr.record.precision == "F":
      byterev32(buf, nread)
    else:
      byterev64(buf, nread)
  let t3 = getMonoTime()
  if sr.verbosity >= 1:
    sr.echo0 &"readBinary seconds read: {t1-t0} cksum: {t2-t1} byterev: {t3-t2}"
  ]#

proc finishReadBinary*(mr: var MilcReader) =
  let pchksum = cast[ptr uint64](addr mr.localchecksum)
  mr.r.xor pchksum[]
  #echo cksums
  #echo "read:   ", sr.localchecksum
  #echo "wanted: ", sr.checksum
  if mr.checksumError:
    mr.echo0 "MILC IO WARNING: checksum mismatch:"
    mr.echo0 "  calculated: ", mr.localchecksum
    mr.echo0 "  expected:   ", mr.checksum

#[
type
  ScidacWriter* = ref object
    verbosity*: int
    lw*: LimeWriter[Writer]
    privateFileXml*: string
    lattice*: seq[int]
    latvol*: int
    volfmt*: int
    fileMd*: string
    privateRecordXml*: string
    record*: ScidacRecordObj
    recordMd*: string
    ildgFormat*: string
    checksum*: MilcChecksum
    checksumXml*: string

template echo0*(sw: ScidacWriter, args: varargs[untyped]) =
  sw.lw.echo0 args

template TAG(x: untyped): untyped = xmltree.`<>`(x)
template TXT(x: untyped): untyped = xmltree.newText(x)

proc createPrivateFileXml(sw: var ScidacWriter) =
  let spacetime = $sw.lattice.len
  let dims = sw.lattice.join(" ")
  var pfxml =
    TAG scidacFile(
      TAG version(TXT "1.1"),
      TAG spacetime(TXT spacetime),
      TAG dims(TXT dims),
      TAG volfmt(TXT "0")
    )
  var s = xmlHeader
  s.add(pfxml, indWidth=0)
  sw.privateFileXml = s.replace("\n","")
  #echo sw.privateFileXml

proc createPrivateRecordXml(sw: var ScidacWriter) =
  template r: untyped = sw.record
  let
    version = r.version
    date = r.date
    #globaldata = $r.globaldata
    recordtype = $r.recordtype
    datatype = r.datatype
    precision = r.precision
    colors = $r.colors
    spins = $r.spins
    typesize = $r.typesize
    datacount = $r.datacount
  var prxml =
    TAG scidacRecord(
      TAG version(TXT version),
      TAG date(TXT date),
      #TAG globaldata(TXT globaldata),
      TAG recordtype(TXT recordtype),
      TAG datatype(TXT datatype),
      TAG precision(TXT precision),
      TAG colors(TXT colors)
    )
  if r.spins>=0:
    prxml.add(TAG spins(TXT spins))
  prxml.add(TAG typesize(TXT typesize))
  prxml.add(TAG datacount(TXT datacount))
  var s = xmlHeader
  s.add(prxml, indWidth=0)
  sw.privateRecordXml = s.replace("\n","")
  #echo sw.privateRecordXml

proc createChecksumXml(sw: var ScidacWriter) =
  let a = toHex(sw.checksum.a)
  let b = toHex(sw.checksum.b)
  var csxml =
    TAG scidacChecksum(
      TAG version(TXT "1.0"),
      TAG suma(TXT a),
      TAG sumb(TXT b)
    )
  var s = xmlHeader
  s.add(csxml, indWidth=0)
  sw.checksumXml = s.replace("\n","")
  #echo sw.checksumXml

proc setRecord*(sw: var ScidacWriter) =
  template r: untyped = sw.record
  let f = initTimeFormat("ddd MMM dd hh:mm:ss yyyy 'UTC'")
  r.version = "1.1"
  r.date = now().utc.format(f)
  #r.globaldata = 0
  r.recordtype = 0
  r.datatype = ""
  r.precision = ""
  r.colors = 0
  r.spins = 0
  r.typesize = 0
  r.datacount = 1

proc setRecordGauge*(sw: var ScidacWriter, prec: string, nc = 3) =
  template r: untyped = sw.record
  let f = initTimeFormat("ddd MMM dd hh:mm:ss yyyy 'UTC'")
  r.version = "1.1"
  r.date = now().utc.format(f)
  #r.globaldata = 0
  r.recordtype = 0
  r.datatype = "QDP_" & prec & $nc & "_ColorMatrix"
  r.precision = prec
  r.colors = nc
  r.spins = -1
  r.typesize = nc*nc*2*(if prec=="F": 4 else: 8)
  r.datacount = sw.lattice.len

proc newScidacWriter*(fn: string, lattice: seq[int], fmd: string,
                      wm=wmCreateOrTruncate, verb=0): ScidacWriter =
  new result
  result.verbosity = verb
  if wm == wmAppend:
    echo "newScidacWriter: append mode not supported!"
    quit(-1)
  var w = newWriter(fn, wm)
  var lw = newLimeWriter(w)
  result.lw = lw
  result.lattice = lattice
  result.latvol = lattice.foldl(a*b)
  result.volfmt = 0
  result.fileMd = fmd
  result.createPrivateFileXml
  let pfxml = result.privateFileXml
  lw.setHeader(true, false, pfxml.len, "scidac-private-file-xml")
  lw.writeHeader
  lw.write pfxml
  lw.setHeader(false, true, fmd.len, "scidac-file-xml")
  lw.writeHeader
  lw.write fmd

proc close*(sw: var ScidacWriter) =
  sw.lw.close

# write binary record header, clear checksum
proc initWriteBinary*(sw: var ScidacWriter; rmd: string) =
  sw.createPrivateRecordXml
  sw.recordMd = rmd
  let prxml = sw.privateRecordXml
  sw.lw.setHeader(true, false, prxml.len, "scidac-private-record-xml")
  sw.lw.writeHeader
  sw.lw.write prxml
  sw.lw.setHeader(false, false, rmd.len, "scidac-record-xml")
  sw.lw.writeHeader
  sw.lw.write rmd
  let sitebytes = sw.record.typesize * sw.record.datacount
  let databytes = sw.latvol * sitebytes
  sw.lw.setHeader(false, false, databytes, "scidac-binary-data")
  sw.lw.writeHeader
  sw.checksum.init

# write hypercube data
proc writeBinary*(sw: var ScidacWriter; buf: pointer; sublattice,offsets: seq[int]) =
  let t0 = getMonoTime()
  let nsites = sublattice.foldl(a*b)
  let sitebytes = sw.record.typesize * sw.record.datacount
  let outbytes = nsites * sitebytes
  if sw.lw.byterev:
    if sw.record.precision == "F":
      byterev32(buf, outbytes)
    else:
      byterev64(buf, outbytes)
  let t1 = getMonoTime()
  when true:
    let chksum = checksumHyper(buf, sitebytes, sw.lattice, sublattice, offsets)
  else:
    let nd = sw.lattice.len
    let ii = nd-1
    var subl = sublattice
    subl[ii] = subl[ii] div 2
    let chksums0 = checksumHyper(buf, sitebytes, sw.lattice, subl, offsets)
    var offs = offsets
    offs[ii] += subl[ii]
    let boff = (nsites div 2) * sitebytes
    let chksums1 = checksumHyper(buf+boff, sitebytes, sw.lattice, subl, offs)
    echo chksums0
    echo chksums1
    let chksum = chksums0 + chksums1
  #echo chksum
  sw.checksum = sw.checksum + chksum
  let t2 = getMonoTime()
  let nwrite = sw.lw.writer.write(buf, sitebytes, sw.lattice, sublattice, offsets)
  if nwrite != outbytes:
    echo "Error: writeBinary short write ", nwrite, " expected ", outbytes
    quit(-1)
  let t3 = getMonoTime()
  if sw.verbosity >= 1:
    sw.echo0 &"writeBinary seconds byterev: {t1-t0} cksum: {t2-t1} write: {t3-t2}"

proc finishWriteBinary*(sw: var ScidacWriter) =
  let pchksum = cast[ptr uint64](addr sw.checksum)
  sw.lw.writer.xor pchksum[]
  sw.createChecksumXml
  sw.lw.setHeader(false, false, sw.checksumXml.len, "scidac-checksum")
  sw.lw.writeHeader
  sw.lw.write sw.checksumXml

proc maybeXml(x: string): string =
  result = x
  try:
    let xml = x.parseXml
    result = $xml
  except:
    discard
]#

proc testRead(fn: string) =
  var mr = newMilcReader(fn)
  template ech0(args: varargs[untyped]) = mr.echo0(args)
  ech0 "Reading Milc: ", fn
  ech0 "---------------------"
  ech0 "Header:"
  ech0 mr.header
  let nd = mr.lattice.len
  var offs = newSeq[int](nd)
  var sublat = mr.lattice
  let rnk = mr.r.myrank
  let nrnk = mr.r.nranks
  let ii = 1
  offs[ii] = (rnk * mr.lattice[ii]) div nrnk
  sublat[ii] = (((rnk+1) * mr.lattice[ii]) div nrnk) - offs[ii]
  #echo rnk, sublat, offs
  let nsites = sublat.foldl(a*b)
  let nbytes = nsites * 4 * 18 * 4
  #echo rnk, " ", nbytes
  var buf = alloc(nbytes)
  mr.readBinary(buf, sublat, offs)
  block:
    let b = cast[ptr UncheckedArray[float32]](buf)
    let n = nbytes div (6*4)
    for j in 0..<n:
      var s = 0.0
      for i in 0..5:
        #echo b[i]
        let t = b[6*j+i]
        s += t*t
      #echo s
  dealloc(buf)
  mr.finishReadBinary
  ech0 "  Computed checksum: ", mr.localChecksum
  #ech0 "  Record checksum:   ", mr.header.checksum
  mr.close

  #[
proc testWrite(fn: string) =
  let lat = @[4,4,4,8]
  let fmd = "Test file metadata"
  var sw = newScidacWriter(fn, lat, fmd)
  template ech0(args: varargs[untyped]) = sw.echo0(args)
  ech0 "Writing scidac: ", fn
  ech0 "---------------------"
  ech0 "Private File Xml:"
  ech0 sw.privateFileXml.parseXml
  ech0 "---------------------"
  ech0 "File Metadata:"
  ech0 sw.fileMd.maybeXml
  sw.setRecordGauge("F")
  sw.initWriteBinary("Binary data 1")
  let n = sw.lw.header.length
  var buf = alloc(n)
  let offs = newSeq[int](lat.len)
  sw.writeBinary(buf, lat, offs)
  dealloc(buf)
  sw.finishWriteBinary()
  sw.close
]#

when isMainModule:
  import os
  let nargs = paramCount()
  case nargs
  of 0:
    let fn = "testwriter.lime"
    #testWrite(fn)
  of 1:
    let fn = paramStr(1)
    testRead(fn)
  else:
    echo "Requires one file argument."
