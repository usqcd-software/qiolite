import pio, lime, crc32
import xmlparser, xmltree, strutils, sequtils, bitops, endians, strformat,
       times, std/monotimes
export pio
template `+`(x: pointer, i: SomeInteger): untyped =
  cast[pointer](cast[ByteAddress](x) + ByteAddress(i))
proc `$`(dur: Duration): string =
  let sec = 1e-6*dur.inMicroseconds.float
  result = sec.formatFloat(ffDecimal, 6)

type
  ScidacChecksum* = tuple[a: uint32, b: uint32]

proc init(x: var ScidacChecksum) =
  x.a = 0
  x.b = 0

proc `+`(x,y: ScidacChecksum): ScidacChecksum =
  result.a = x.a xor y.a
  result.b = x.b xor y.b

proc `$`(x: ScidacChecksum): string =
  result = "(a: 0x" & toHex(x.a).toLower & ", b: 0x" & toHex(x.b).toLower & ")"

type
  ScidacRecordObj* = object
    version*: string
    date*: string
    #globaldata*: int
    recordtype*: int
    datatype*: string
    precision*: string
    colors*: int
    spins*: int
    typesize*: int
    datacount*: int
  ScidacRecord* = ref ScidacRecordObj

type
  ScidacReader* = ref object
    verbosity*: int
    lr*: LimeReader[Reader]
    privateFileXml*: string
    lattice*: seq[int]
    latvol*: int
    volfmt*: int
    fileMd*: string
    privateRecordXml*: string
    record*: ScidacRecordObj
    recordMd*: string
    ildgFormat*: string
    localChecksum*: ScidacChecksum
    checksum*: ScidacChecksum
    atEnd*: bool

template echo0*(sr: ScidacReader, args: varargs[untyped]) =
  sr.lr.echo0 args

proc nextRecord*(sr: var ScidacReader) =
  if sr.lr.header.limetypeString == "scidac-binary-data" or
     sr.lr.header.limetypeString == "ildg-binary-data":
    sr.lr.nextRecord
  if sr.lr.header.limetypeString == "scidac-checksum":
    sr.lr.nextRecord
  if sr.lr.atEnd:
    sr.atEnd = true
    return
  if sr.lr.header.limetypeString != "scidac-private-record-xml":
    echo "ScidacReader: unexpected limetype ", sr.lr.header.limetypeString,
     " expected scidac-private-record-xml"
    quit(-1)
  sr.privateRecordXml = sr.lr.read
  let prxml = parseXml(sr.privateRecordXml)
  sr.record.version = prxml.child("version").innerText
  sr.record.date = prxml.child("date").innerText
  sr.record.precision = prxml.child("precision").innerText
  sr.record.typesize = prxml.child("typesize").innerText.parseInt
  sr.record.datacount = prxml.child("datacount").innerText.parseInt
  sr.lr.nextRecord
  if sr.lr.header.limetypeString != "scidac-record-xml":
    echo "ScidacReader: unexpected limetype ", sr.lr.header.limetypeString,
     " expected scidac-record-xml"
    quit(-1)
  sr.recordMd = sr.lr.read
  sr.lr.nextRecord
  if sr.lr.header.limetypeString == "ildg-format":
    sr.ildgFormat = sr.lr.read
    sr.lr.nextRecord
  sr.localChecksum.init
  sr.checksum.init

proc newScidacReader*(fn: string, verb=0): ScidacReader =
  new result
  result.verbosity = verb
  var r = newReader(fn)
  var lr = newLimeReader(r)
  result.lr = lr
  #result.lattice = lattice
  if lr.header.limetypeString != "scidac-private-file-xml":
    echo "ScidacReader: unexpected limetype ", lr.header.limetypeString,
     " expected scidac-private-file-xml"
    quit(-1)
  result.privateFileXml = lr.read
  var pfxml = parseXml(result.privateFileXml)
  #echo pfxml
  let dims = pfxml.child("dims").innerText.strip.split.mapit(parseInt(it))
  result.lattice = dims
  result.latvol = dims.foldl(a*b)
  #echo "dims: ", dims
  let volfmt = pfxml.child("volfmt").innerText.parseInt
  result.volfmt = volfmt
  #echo "volfmt: ", volfmt
  lr.nextRecord
  if lr.header.limetypeString != "scidac-file-xml":
    echo "ScidacReader: unexpected limetype ", lr.header.limetypeString,
     " expected scidac-file-xml"
    quit(-1)
  result.fileMd = lr.read
  lr.nextRecord
  result.nextRecord

proc close*(sr: var ScidacReader) =
  sr.lr.close

proc checksumHyper(buf: pointer; elemsize: int;
                   lattice,sublattice,offsets: seq[int]): ScidacChecksum =
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
  var sumA,sumB = 0'u32
  for i in 0..<nsites:
    let c = crc32(buf+i*elemsize, elemsize)
    sumA = sumA xor rotateLeftBits(c, lex mod 29)
    sumB = sumB xor rotateLeftBits(c, lex mod 31)
    var j = 0
    while j < nd:
      x[j] += 1
      lex += dlex[j]
      if x[j] < sublattice[j]:
        break
      x[j] = 0
      lex -= dlex[j] * sublattice[j]
      j += 1
  result.a = sumA
  result.b = sumB

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

proc readBinary*(sr: var ScidacReader; buf: pointer; sublattice,offsets: seq[int]) =
  let t0 = getMonoTime()
  if sr.lr.header.limetypeString != "scidac-binary-data" and
     sr.lr.header.limetypeString != "ildg-binary-data":
    echo "ScidacReader: unexpected limetype ", sr.lr.header.limetypeString,
     " expected scidac-binary-data or ildg-binary-data"
    quit(-1)
  # check record size
  let sitebytes = sr.record.typesize * sr.record.datacount
  let databytes = sr.latvol * sitebytes
  let reclen = sr.lr.header.length
  if databytes != reclen:
    echo "Error: readBinary record length ", reclen, " != ", databytes
    quit(-1)
  let nd = sr.lattice.len
  var nsites = sublattice.foldl(a*b)
  let nread = sr.lr.reader.read(buf, sitebytes, sr.lattice, sublattice, offsets)
  if nread != nsites*sitebytes:
    echo "Error: readBinary short read ", nread, " expected ", nsites*sitebytes
    quit(-1)
  let t1 = getMonoTime()
  when true:
    let chksums = checksumHyper(buf, sitebytes, sr.lattice, sublattice, offsets)
  else:
    let ii = nd-1
    var subl = sublattice
    subl[ii] = subl[ii] div 2
    let chksums0 = checksumHyper(buf, sitebytes, sr.lattice, subl, offsets)
    var offs = offsets
    offs[ii] += subl[ii]
    let boff = (nsites div 2) * sitebytes
    let chksums1 = checksumHyper(buf+boff, sitebytes, sr.lattice, subl, offs)
    echo chksums0
    echo chksums1
    let chksums = chksums0 + chksums1
  #echo chksums
  sr.localChecksum.a = sr.localChecksum.a xor chksums.a
  sr.localChecksum.b = sr.localChecksum.b xor chksums.b
  let t2 = getMonoTime()
  if sr.lr.byterev:
    if sr.record.precision == "F":
      byterev32(buf, nread)
    else:
      byterev64(buf, nread)
  let t3 = getMonoTime()
  if sr.verbosity >= 1:
    sr.echo0 &"readBinary seconds read: {t1-t0} cksum: {t2-t1} byterev: {t3-t2}"

proc finishReadBinary*(sr: var ScidacReader) =
  if sr.lr.header.limetypeString != "scidac-binary-data" and
     sr.lr.header.limetypeString != "ildg-binary-data":
    echo "ScidacReader: unexpected limetype ", sr.lr.header.limetypeString,
     " expected scidac-binary-data or ildg-binary-data"
    quit(-1)
  sr.lr.nextRecord
  if sr.lr.header.limetypeString != "scidac-checksum":
    echo "ScidacReader: unexpected limetype ", sr.lr.header.limetypeString,
     " expected scidac-checksum"
    quit(-1)
  let cksums = sr.lr.read.parseXml
  sr.checksum.a = fromHex[uint32] cksums.child("suma").innerText
  sr.checksum.b = fromHex[uint32] cksums.child("sumb").innerText
  #echo sr.localchecksum
  let pchksum = cast[ptr uint64](addr sr.localchecksum)
  sr.lr.reader.xor pchksum[]
  #echo cksums
  #echo "read:   ", sr.localchecksum
  #echo "wanted: ", sr.checksum
  if sr.localchecksum != sr.checksum:
    sr.echo0 "SciDAC IO WARNING: checksum mismatch:"
    sr.echo0 "  calculated: ", sr.localchecksum
    sr.echo0 "  expected:   ", sr.checksum


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
    checksum*: ScidacChecksum
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

proc newScidacWriter*(fn: string, lattice: seq[int], fmd: string, verb=0): ScidacWriter =
  new result
  result.verbosity = verb
  var w = newWriter(fn)
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

proc testRead(fn: string) =
  var sr = newScidacReader(fn)
  template ech0(args: varargs[untyped]) = sr.echo0(args)
  ech0 "Reading scidac: ", fn
  ech0 "---------------------"
  ech0 "Private File Xml:"
  ech0 sr.privateFileXml.parseXml
  ech0 "---------------------"
  ech0 "File Metadata:"
  ech0 sr.fileMd.maybeXml
  while not sr.atEnd:
    ech0 "---------------------"
    ech0 "Private Record Xml:"
    ech0 sr.privateRecordXml.parseXml
    ech0 "---------------------"
    ech0 "Record Metadata:"
    ech0 sr.recordMd.maybeXml
    ech0 "---------------------"
    ech0 "ILDG Format:"
    ech0 sr.ildgFormat.maybeXml
    ech0 "---------------------"
    ech0 "Record data:"
    ech0 "  Limetype: ", sr.lr.header.limetypeString
    ech0 "  Bytes: ", sr.lr.header.length
    let nd = sr.lattice.len
    var offs = newSeq[int](nd)
    var sublat = sr.lattice
    let rnk = sr.lr.reader.myrank
    let nrnk = sr.lr.reader.nranks
    let ii = 1
    offs[ii] = (rnk * sr.lattice[ii]) div nrnk
    sublat[ii] = (((rnk+1) * sr.lattice[ii]) div nrnk) - offs[ii]
    #echo rnk, sublat, offs
    let nsites = sublat.foldl(a*b)
    let nbytes = nsites * sr.record.typesize * sr.record.datacount
    #echo rnk, " ", nbytes
    var buf = alloc(nbytes)
    sr.readBinary(buf, sublat, offs)
    dealloc(buf)
    sr.finishReadBinary
    ech0 "  Computed checksum: ", sr.localChecksum
    ech0 "  Record checksum:   ", sr.checksum
    sr.nextRecord
  sr.close

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

when isMainModule:
  import os
  let nargs = paramCount()
  case nargs
  of 0:
    let fn = "testwriter.lime"
    testWrite(fn)
  of 1:
    let fn = paramStr(1)
    testRead(fn)
  else:
    echo "Requires one file argument."



# scidac-private-file-xml
# <?xml version="1.0" encoding="UTF-8"?><scidacFile><version>1.1</version><spacetime>4</spacetime><dims>32 32 32 32 </dims><volfmt>0</volfmt></scidacFile>

# scidac-private-record-xml
# <?xml version="1.0" encoding="UTF-8"?><scidacRecord><version>1.1</version><date>Fri Oct 23 05:37:48 2020 UTC</date><recordtype>0</recordtype><datatype>QUDA_DNc3_GaugeField</datatype><precision>D</precision><colors>3</colors><typesize>144</typesize><datacount>4</datacount></scidacRecord>

# scidac-private-record-xml
# <?xml version="1.0" encoding="UTF-8"?><scidacRecord><version>1.0</version><date>Fri Apr 21 22:16:25 2006 UTC</date><globaldata>0</globaldata><datatype>QDP_F3_ColorMatrix</datatype><precision>F</precision><colors>3</colors><spins>4</spins><typesize>72</typesize><datacount>4</datacount></scidacRecord>

# scidac-checksum
# <?xml version="1.0" encoding="UTF-8"?><scidacChecksum><version>1.0</version><suma>1f5fbfee</suma><sumb>43bcbf54</sumb></scidacChecksum>
