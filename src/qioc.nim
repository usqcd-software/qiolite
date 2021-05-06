import exporth
import scidacio
import strutils
include system/ansi_c
template toHex(x: ptr typed): untyped = toHex(cast[uint](x))
template `+`(x: ptr char, i: SomeInteger): untyped =
  cast[ptr char](cast[ByteAddress](x) + ByteAddress(i))
#template uarray(T: typedesc, n: int): untyped =
#  cast[ptr UncheckedArray[T]](create(T, n))[]
#template dealloc[T](x: UncheckedArray[T]) =
#  dealloc(cast[ptr T](unsafeaddr x))
template `[]`[T](x: ptr T, i: int): untyped =
  (cast[ptr UncheckedArray[T]](x))[][i]
template `&`[T](x: seq[T]): untyped = cast[ptr T](unsafeaddr x[0])
#template to(p: ptr UncheckedArray, n: SomeInteger): untyped =
#  @toOpenArray(p, 0, n-1)
proc toSeq[T](p: ptr UncheckedArray[T], n: SomeInteger): seq[T] =
  result.newSeq(n)
  for i in 0..<n: result[i] = p[][i]
proc toSeq[T,R](p: ptr UncheckedArray[T], n: SomeInteger, r: typedesc[R]): seq[R] =
  result.newSeq(n)
  for i in 0..<n: result[i] = R(p[][i])

{.emit:"#define NimMain NimMain_qioc".}
proc NimMain_qioc {.importc.}
proc init =
  var inited {.global.} = false
  if not inited:
    inited = true
    NimMain_qioc()

{.pragma: exprt, exporth.}

var eh {.compiletime.} = newExportH()

eh.add:
  const
    ## Return codes
    QIO_SUCCESS* = 0'i32
    QIO_EOF* = -1'i32
    QIO_ERR_BAD_WRITE_BYTES* = -2'i32
    QIO_ERR_OPEN_READ* = -3'i32
    QIO_ERR_OPEN_WRITE* = -4'i32
    QIO_ERR_BAD_READ_BYTES* = -5'i32
    #QIO_ERR_ALLOC* = (- 6)
    #QIO_ERR_CLOSE* = (- 7)
    #QIO_ERR_INFO_MISSED* = (- 8)
    #QIO_ERR_BAD_SITELIST* = (- 9)
    #QIO_ERR_PRIVATE_FILE_INFO* = (- 10)
    #QIO_ERR_PRIVATE_REC_INFO* = (- 11)
    #QIO_BAD_XML* = (- 12)
    #QIO_BAD_ARG* = (- 13)
    #QIO_CHECKSUM_MISMATCH* = (- 14)
    #QIO_ERR_FILE_INFO* = (- 15)
    #QIO_ERR_REC_INFO* = (- 16)
    #QIO_ERR_CHECKSUM_INFO* = (- 17)
    #QIO_ERR_SKIP* = (- 18)
    #QIO_ERR_BAD_TOTAL_BYTES* = (- 19)
    #QIO_ERR_BAD_GLOBAL_TYPE* = (- 20)
    #QIO_ERR_BAD_VOLFMT* = (- 21)
    #QIO_ERR_BAD_IONODE* = (- 22)
    #QIO_ERR_BAD_SEEK* = (- 23)
    #QIO_ERR_BAD_SUBSET* = (- 24)

var verbosity = 0'i32
eh.add:
  const
    ## Enumerate in order of increasing verbosity
    QIO_VERB_OFF* = 0'i32
    QIO_VERB_LOW* = 1'i32
    QIO_VERB_MED* = 2'i32
    QIO_VERB_REG* = 3'i32
    QIO_VERB_HIGH* = 4'i32
    QIO_VERB_DEBUG* = 5'i32
  proc QIO_verbose*(level: int32): int32 =
    result = verbosity
    verbosity = level
  proc QIO_verbosity*(): int32 =
    result = verbosity

eh.add:
  type
    QIO_String* = object
      string*: ptr char
      length*: csize_t
  template len(x: ptr QIO_String): untyped = x[].length
  template `len=`(x: ptr QIO_String, y: typed): untyped = x[].length = y
  template str(x: ptr QIO_String): untyped = x[].`string`
  template `str=`(x: ptr QIO_String, y: typed): untyped = x[].`string` = y
  proc QIO_string_create*(): ptr QIO_String =
    #result = create(QIO_String, 1)
    result = cast[ptr QIO_String](cmalloc(csize_t sizeof(QIO_String)))
    result.len = 0
    result.str = nil
  proc QIO_string_destroy*(qs: ptr QIO_String) =
    if qs != nil:
      if qs.len > 0:
        qs.len = 0
        #dealloc(qs.str)
        cfree(qs.str)
        qs.str = nil
      #dealloc(qs)
      cfree(qs)
  proc QIO_string_length*(qs: ptr QIO_String): csize_t =
    if qs == nil:
      cfprintf(cstderr,"QIO_string_length: Attempt to get length of NULL QIO_String*\n")
      discard cfflush(cstderr)
      quit(-1)
    result = qs.len
  #proc QIO_string_realloc*(qs: ptr QIO_String, length: int32) =
  #  let n = cstrlen(str) + 2  # QIO seems to pad this sometimes
  #  qs.len = n
  #  #qs.str = resize(qs.str, n)
  #  qs.str = cast[ptr char](crealloc(qs.str, n))
  #  cmemcpy(qs.str, str, n-2)
  proc QIO_string_set*(qs: ptr QIO_String, str: cstring) =
    if qs == nil:
      cfprintf(cstderr,"QIO_string_set: Attempt to set NULL QIO_String*\n")
      discard cfflush(cstderr)
      quit(-1)
    if str == nil:
      if qs.len>0:
        qs.len = 0
        #dealloc(qs.str)
        cfree(qs.str)
        qs.str = nil
    else:
      let n = cstrlen(str) + 2  # QIO seems to pad this sometimes
      qs.len = n
      #qs.str = resize(qs.str, n)
      qs.str = cast[ptr char](crealloc(qs.str, n))
      cmemcpy(qs.str, str, n-2)
  proc QIO_string_ptr*(qs: ptr QIO_String): ptr char =
    #echo "QIO_string_ptr qs.str: ", toHex(cast[uint](qs.str))
    #flushFile(stdout)
    qs.str
  proc QIO_string_copy*(dest: ptr QIO_String, src: QIO_String) =
    let n = src.length
    dest.str = cast[ptr char](crealloc(dest.str, n))
    cmemcpy(dest.str, src.`string`, n)
    dest.len = n
  proc QIO_string_append(qs: ptr QIO_String, str: Const[cstring]) = discard

proc `$`(qs: ptr QIO_String): string =
  let n = qs.len - 2  # assume 2 nulls
  let buf = cast[ptr UncheckedArray[char]](QIO_string_ptr(qs))
  result = newString(n)
  for i in 0..<n:
    result[i] = buf[i]
  #echo n, ": ", result

eh.add:
  ## Support for host file conversion
  const
    ## type
    QIO_SINGLE_PATH* = 0
    QIO_MULTI_PATH* = 1
  type
    DML_io_node_t* = proc(rank: int32): int32 {.nimcall.}
    DML_master_io_node_t* = proc(): int32 {.nimcall.}
    QIO_Filesystem* = object
      number_io_nodes*: int32
      `type`*: int32 # Is node_path specified?
      my_io_node*: DML_io_node_t # Mapping as on compute nodes
      master_io_node*: DML_master_io_node_t # As on compute nodes
      io_node*: ptr int32 # Only if number_io_nodes != number_of_nodes
      node_path*: cstringArray # Only if type = QIO_MULTI_PATH

eh.add:
  const
    ## serpar
    QIO_SERIAL* = 0'i32
    QIO_PARALLEL* = 1'i32
  const
    ## volfmt
    QIO_UNKNOWN* = -1'i32
    QIO_SINGLEFILE* = 0'i32
    QIO_MULTIFILE* = 1'i32
    QIO_PARTFILE* = 2'i32
    QIO_PARTFILE_DIR* = 3'i32
  const
    ## mode
    QIO_CREAT* = 0'i32
    QIO_TRUNC* = 1'i32
    QIO_APPEND* = 2'i32
  const
    ## ildgstyle: ILDG style file
    QIO_ILDGNO* = 0'i32
    QIO_ILDGLAT* = 1'i32
  type
    QIO_Iflag* = object
      serpar*: int32
      volfmt*: int32
    QIO_Oflag* = object
      serpar*: int32
      mode*: int32
      ildgstyle*: int32
      ildgLFN*: ptr QIO_String

eh.add:
  const
    ## recordtype
    QIO_FIELD* = 0'i32
    QIO_GLOBAL* = 1'i32
    QIO_HYPER* = 2'i32
  type
    QIO_RecordInfo* = object
      version*: cstring
      date*: cstring
      recordtype*: int32
      spacetime*: int32
      hyperlower*: ptr int32
      hyperupper*: ptr int32
      datatype*: cstring
      precision*: cstring
      colors*: int32
      spins*: int32
      typesize*: int32
      datacount*: int32

  proc QIO_create_record_info*(recordtype: int32, lower: ptr int32, upper: ptr int32,
                               n: int32, datatype: cstring, precision: cstring,
                               colors: int32, spins: int32, typesize: int32,
                               datacount: int32): ptr QIO_RecordInfo =
    result = create(QIO_RecordInfo, 1)
    result.version = nil
    result.date = nil
    result.recordtype = recordtype
    result.spacetime = n
    result.hyperlower = lower
    result.hyperupper = upper
    result.datatype = datatype    # FIXME copy?
    result.precision = precision  # FIXME copy?
    result.colors = colors
    result.spins = spins
    result.typesize = typesize
    result.datacount = datacount

  proc QIO_destroy_record_info*(record_info: ptr QIO_RecordInfo) =
    dealloc(record_info)
  proc QIO_get_record_date*(record_info: ptr QIO_RecordInfo): cstring =
    result = record_info.date
  proc QIO_get_datatype*(record_info: ptr QIO_RecordInfo): cstring =
    result = record_info.datatype
  proc QIO_get_precision*(record_info: ptr QIO_RecordInfo): cstring =
    result = record_info.precision
  proc QIO_get_colors*(record_info: ptr QIO_RecordInfo): cint =
    result = record_info.colors
  proc QIO_get_spins*(record_info: ptr QIO_RecordInfo): cint =
    result = record_info.spins
  proc QIO_get_typesize*(record_info: ptr QIO_RecordInfo): cint =
    result = record_info.typesize
  proc QIO_get_datacount*(record_info: ptr QIO_RecordInfo): cint =
    result = record_info.datacount

#[
# wordsize in bytes
proc wordsize(x: cstring): int32 =
  result = 8;
  if x[0] == 'F':
    result = 4

proc prec(x: int32): cstring =
  let precs {.global.} = [cstring "F", "D"]
  echo x
  let i = (x div 4) - 1
  echo i
  result = precs[i]
]#

proc hyperindex(x: seq[cint]; subl,offs: seq[int]): int =
  let n = x.len
  for i in countdown(n-1,0):
    result = result*subl[i] + (x[i]-offs[i])

eh.add:
  type
    ## For collecting and passing layout information
    QIO_Layout* = object
      node_number*: proc (coords: ptr int32): int32 {.nimcall.}
      node_index*: proc (coords: ptr int32): int32 {.nimcall.}
      get_coords*: proc (coords: ptr int32; node: int32; index: int32) {.nimcall.}
      num_sites*: proc (node: int32): int32 {.nimcall.}
      latsize*: ptr UncheckedArray[int32]
      latdim*: int32
      volume*: csize_t
      sites_on_node*: csize_t
      this_node*: int32
      number_of_nodes*: int32
    QIO_Reader* = object
      layout*: ptr QIO_Layout
      reader*: pointer
      #lrl_file_in*: ptr LRL_FileReader
      #volfmt*: cint
      #serpar*: cint
      #format*: cint
      #ildgstyle*: cint
      #ildg_precision*: cint
      #layout*: ptr DML_Layout
      #sites*: ptr DML_SiteList
      #read_state*: cint
      #xml_record*: QIO_String
      #ildgLFN*: ptr QIO_String
      record_info*: QIO_RecordInfo
      #last_checksum*: DML_Checksum
      #dml_record_in*: ptr DML_RecordReader
    QIO_Writer* = object
      layout*: ptr QIO_Layout
      writer*: pointer
      #lrl_file_out*: ptr LRL_FileWriter
      #volfmt*: cint
      #serpar*: cint
      #ildgstyle*: cint
      #ildgLFN*: ptr QIO_String
      #layout*: ptr DML_Layout
      #sites*: ptr DML_SiteList
      #last_checksum*: DML_Checksum
      #dml_record_out*: ptr DML_RecordWriter

  proc setRecordInfo*(qr: ptr QIO_Reader) =
    var sr = cast[ScidacReader](qr.reader)
    template r: untyped = sr.record
    qr.record_info.version = r.version
    qr.record_info.date = r.date
    #qr.recordtype = recordtype
    #qr.spacetime = n
    #qr.hyperlower = lower
    #qr.hyperupper = upper
    #qr.datatype = datatype    # FIXME copy?
    qr.record_info.precision = r.precision.cstring
    qr.record_info.datacount = r.datacount.int32
    #qr.colors = colors
    #qr.spins = spins
    #qr.typesize = typesize

  proc QIO_open_read*(xml_file: ptr QIO_String; filename: cstring;
                      layout: ptr QIO_Layout; fs: ptr QIO_Filesystem;
                      iflag: ptr QIO_Iflag): ptr QIO_Reader =
    init()
    result = create(QIO_Reader, 1)
    result.layout = layout
    var sr = newScidacReader($filename)
    GC_ref(sr)
    result.reader = cast[pointer](sr)
    QIO_string_set(xml_file, sr.fileMd)
    result.setRecordInfo

  proc QIO_close_read*(qr: ptr QIO_Reader): int32 =
    var sr = cast[ScidacReader](qr.reader)
    sr.close
    GC_unref(sr)
    qr.reader = nil
    dealloc(qr)
    result = QIO_SUCCESS

  proc QIO_open_write*(xml_file: ptr QIO_String; filename: cstring; volfmt: cint;
                       layout: ptr QIO_Layout; fs: ptr QIO_Filesystem;
                       oflag: ptr QIO_Oflag): ptr QIO_Writer =
    init()
    if volfmt != QIO_SINGLEFILE:
      echo "ERROR: unsupported volfmt: ", volfmt
      quit(-1)
    result = create(QIO_Writer, 1)
    result.layout = layout
    let lat = toSeq(layout.latsize, layout.latdim, int)
    var wr = newScidacWriter($filename, lat, $xml_file)
    GC_ref(wr)
    result.writer = cast[pointer](wr)

  proc QIO_close_write*(qw: ptr QIO_Writer): int32 =
    var sw = cast[ScidacWriter](qw.writer)
    sw.close
    GC_unref(sw)
    qw.writer = nil
    dealloc(qw)
    result = QIO_SUCCESS

  proc QIO_get_reader_latdim*(qr: ptr QIO_Reader): cint =
    var sr = cast[ScidacReader](qr.reader)
    result = sr.lattice.len.cint

  proc QIO_get_reader_latsize*(qr: ptr QIO_Reader): ptr cint =
    var sr = cast[ScidacReader](qr.reader)
    let nd = sr.lattice.len
    result = create(cint, nd)
    var lat = cast[ptr UncheckedArray[cint]](result)
    for i in 0..<nd:
      lat[i] = cint sr.lattice[i]

  proc QIO_get_reader_last_checksuma*(qr: ptr QIO_Reader): uint32 =
    var sr = cast[ScidacReader](qr.reader)
    result = sr.checksum.a
  proc QIO_get_reader_last_checksumb*(qr: ptr QIO_Reader): uint32 =
    var sr = cast[ScidacReader](qr.reader)
    result = sr.checksum.b

  #proc QIO_set_reader_pointer*(qio_in: ptr QIO_Reader; offset: int): cint = discard
  #proc QIO_get_reader_pointer*(qio_in: ptr QIO_Reader): int = discard
  #proc QIO_get_ILDG_LFN*(qio_in: ptr QIO_Reader): cstring = discard
  #proc QIO_get_ildgstyle*(qr: ptr QIO_Reader): cint = discard
  #proc QIO_get_reader_volfmt*(qr: ptr QIO_Reader): cint = discard
  #proc QIO_get_reader_format*(qr: ptr QIO_Reader): cint = discard
  #proc QIO_set_record_info*(qr: ptr QIO_Reader; rec_info: ptr QIO_RecordInfo) = discard
  proc QIO_get_writer_last_checksuma*(qw: ptr QIO_Writer): uint32 =
    var sw = cast[ScidacWriter](qw.writer)
    result = sw.checksum.a
  proc QIO_get_writer_last_checksumb*(qw: ptr QIO_Writer): uint32 =
    var sw = cast[ScidacWriter](qw.writer)
    result = sw.checksum.b

  proc QIO_read_record_info*(qr: ptr QIO_Reader; record_info: ptr QIO_RecordInfo;
                             xml_record: ptr QIO_String): cint =
    var sr = cast[ScidacReader](qr.reader)
    QIO_string_set(xml_record, sr.recordMd)
    record_info[] = qr.record_info   # FIXME: ptrs
    result = QIO_SUCCESS

  proc QIO_read_record_data*(qr: ptr QIO_Reader;
                             put: proc (buf: cstring; index: csize_t; count: cint;
                                        arg: pointer) {.nimcall.};
                            datum_size: csize_t; word_size: cint; arg: pointer): cint =
    var sr = cast[ScidacReader](qr.reader)
    template r: untyped = sr.record
    let nsites = qr.layout.sites_on_node
    let nbytes = nsites * datum_size
    let objcount = r.datacount.cint
    let nd = qr.layout.latdim
    var x = newSeq[cint](nd)
    let this_node = qr.layout.this_node
    var sublattice = newSeq[int](nd)
    var hypermin = sr.lattice
    var hypermax = newSeq[int](nd)
    for i in countup(0.cint, nsites.cint-1):
      qr.layout.get_coords(&x, this_node, i)
      #echo i, " ", x
      for j in 0..<nd:
        hypermin[j] = min(hypermin[j], x[j])
        hypermax[j] = max(hypermax[j], x[j])
    #echo hypermin, " ", hypermax
    for j in 0..<nd:
      sublattice[j] = hypermax[j] - hypermin[j] + 1
    var buf = create(char, nbytes)
    sr.readBinary(buf, sublattice, hypermin)
    for i in countup(0'i32, nsites.int32-1):
      qr.layout.get_coords(&x, this_node, i)
      let j = hyperindex(x, sublattice, hypermin)
      let tbuf = buf + j*datum_size.int
      put(tbuf, uint i, objcount, arg)
    dealloc(buf)
    sr.finishReadBinary
    result = QIO_SUCCESS

  proc QIO_next_record*(qr: ptr QIO_Reader): cint =
    var sr = cast[ScidacReader](qr.reader)
    sr.nextRecord
    result = QIO_SUCCESS
    if sr.atEnd:
      result = QIO_EOF

  proc QIO_read*(qr: ptr QIO_Reader; record_info: ptr QIO_RecordInfo;
                 xml_record: ptr QIO_String;
                 put: proc(buf: cstring; index: csize_t; count: cint;
                           arg: pointer) {.nimcall.},
                  datum_size: csize_t; word_size: cint; arg: pointer): cint =
    var sr = cast[ScidacReader](qr.reader)
    QIO_string_set(xml_record, sr.recordMd)
    result = QIO_read_record_data(qr, put, datum_size, word_size, arg)

  proc QIO_write*(qw: ptr QIO_Writer; record_info: ptr QIO_RecordInfo;
                  xml_record: ptr QIO_String;
                  get: proc(buf: ptr char; index: csize_t; count: cint;
                            arg: pointer) {.nimcall.};
                  datum_size: csize_t; word_size: cint; arg: pointer): cint =
    var sw = cast[ScidacWriter](qw.writer)
    template r: untyped = sw.record
    sw.setRecord()
    r.datatype = $record_info.datatype
    r.precision = $record_info.precision
    r.colors = record_info.colors
    r.spins = record_info.spins
    r.typesize = record_info.typesize
    r.datacount = record_info.datacount
    sw.initWriteBinary($xml_record)
    let nsites = qw.layout.sites_on_node
    let nbytes = nsites * datum_size
    let objcount = r.datacount.cint
    let nd = qw.layout.latdim
    var x = newSeq[cint](nd)
    let this_node = qw.layout.this_node
    var sublattice = newSeq[int](nd)
    var hypermin = sw.lattice
    var hypermax = newSeq[int](nd)
    for i in countup(0.cint, nsites.cint-1):
      qw.layout.get_coords(&x, this_node, i)
      #echo i, " ", x
      for j in 0..<nd:
        hypermin[j] = min(hypermin[j], x[j])
        hypermax[j] = max(hypermax[j], x[j])
    #echo hypermin, " ", hypermax
    for j in 0..<nd:
      sublattice[j] = hypermax[j] - hypermin[j] + 1
    var buf = create(char, nbytes)
    for i in countup(0'i32, nsites.int32-1):
      qw.layout.get_coords(&x, this_node, i)
      let j = hyperindex(x, sublattice, hypermin)
      let tbuf = buf + j*datum_size.int
      get(tbuf, uint i, objcount, arg)
    sw.writeBinary(buf, sublattice, hypermin)
    dealloc(buf)
    sw.finishWriteBinary()
    result = QIO_SUCCESS

eh.write("qio.h")

#when isMainModule:
