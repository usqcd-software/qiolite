import mpi
import strformat, sequtils
template `&`(x: seq): untyped = addr x[0]

type
  Reader* = ref object
    filename*: string
    isOpen*: bool
    comm*: MPI_Comm
    fh*: MPI_File
    filesize*: int
    nranks*: int
    myrank*: int
    weInitedMpi*: bool

template echo0*(rd: Reader, args: varargs[untyped]) =
  if rd.myrank == 0:
    echo args

proc `xor`*(rd: Reader, x: var uint64) =
  var y = x
  let send = cast[pointer](addr y)
  let recv = cast[pointer](addr x)
  let err = MPI_Allreduce(send, recv, 1, MPI_UNSIGNED_LONG_LONG, MPI_BXOR, rd.comm)

proc open(rd: var Reader) =
  if rd.isOpen:
    return
  let amode = MPI_MODE_RDONLY
  let info = MPI_INFO_NULL
  var err = MPI_File_open(rd.comm, rd.filename.cstring, amode, info, addr rd.fh)
  if err != MPI_SUCCESS:
    echo "open failed with error ", err
    quit(-1)
  rd.isOpen = true
  var size: MPI_Offset
  err = MPI_File_get_size(rd.fh, addr size)
  if err != MPI_SUCCESS:
    echo "get size failed with error ", err
    quit(-1)
  rd.filesize = size

proc initPio*() =
  var inited = 0'i32
  var err = MPI_Initialized(addr inited)
  if inited == 0:
    err = MPI_Init()

proc finiPio*() =
  var err = MPI_Finalize()

proc newReader*(fn: string): Reader =
  result.new
  var inited = 0'i32
  var err = MPI_Initialized(addr inited)
  if inited == 0:
    err = MPI_Init()
    result.weInitedMpi = true
  result.filename = fn
  result.isOpen = false
  result.comm = MPI_COMM_WORLD
  var size, rank: cint
  err = MPI_Comm_size(result.comm, addr size)
  err = MPI_Comm_rank(result.comm, addr rank)
  result.nranks = size
  result.myrank = rank
  open result

proc close*(rd: var Reader) =
  if rd.isOpen:
    rd.isOpen = false
    discard MPI_File_close(addr rd.fh)
    if rd.weInitedMpi:
      var err = MPI_Finalize()

proc size*(rd: var Reader): int =
  var size: MPI_Offset
  let err = MPI_File_get_size(rd.fh, addr size)
  result = size

proc seekTo*(rd: var Reader, offset: int) =
  var err = MPI_File_seek(rd.fh, offset, MPI_SEEK_SET)
  #rd.echoAll "seekTo: ", offset, "  err: ", err

proc read*(rd: var Reader, buf: pointer, nbytes: int): int =
  if not rd.isOpen:
    echo "ERROR: Reader read: not open"
    quit(-1)
  var pos: MPI_Offset
  var err = MPI_File_get_position(rd.fh, addr pos)
  if err != MPI_SUCCESS:
    echo "MPI_File_get_position failed with error ", err
    quit(-1)
  if pos >= rd.filesize:
    return 0
  #rd.echoAll "reading: ", nbytes
  #let nread = rd.fh.readBuffer(buf, nbytes)
  var status: MPI_Status
  err = MPI_File_read_all(rd.fh, buf, nbytes.cint, MPI_CHAR, addr status)
  if err != MPI_SUCCESS:
    echo "pio read MPI_File_read_all err: ", err
  var nread: MPI_Count
  err = MPI_Get_elements_x(addr status, MPI_CHAR, addr nread)
  if err != MPI_SUCCESS:
    echo "pio read MPI_Get_count err: ", err
  result = toInt(nread)
  #if nread != nbytes:
  #  rd.echoAll &"ERROR: bytes read ({nread}) < nbytes ({nbytes})"
template read*(rd: var Reader, buf: ptr typed, nbytes: SomeInteger): int =
  rd.read(cast[pointer](buf), int(nbytes))
template read*[T](rd: var Reader, buf: var T): int =
  rd.read(cast[pointer](addr buf), sizeof(T))

proc read*(rd: var Reader, val: var SomeNumber): int =
  let buf = addr val
  let nbytes = sizeof(val)
  rd.read(buf, nbytes)

proc read*(rd: var Reader, val: var string): int =
  let buf = addr val[0]
  let nbytes = val.len
  rd.read(buf, nbytes)

proc read*(rd: var Reader; buf: pointer; elemsize: int;
           lattice,sublattice,offsets: seq[int]): int =
  #rd.echo0 "pio read"
  var pos: MPI_Offset
  var err = MPI_File_get_position(rd.fh, addr pos)
  if err != MPI_SUCCESS:
    echo "MPI_File_get_position failed with error ", err
    quit(-1)
  #rd.echo0 "  pos: ", toInt(pos)

  var disp0: MPI_Offset
  var etype0: MPI_Datatype
  var filetype0: MPI_Datatype
  var datarep0 = newString(MPI_MAX_DATAREP_STRING)
  err = MPI_File_get_view(rd.fh, addr disp0, addr etype0,
                          addr filetype0, datarep0)
  if err != MPI_SUCCESS:
    echo "MPI_File_get_view failed with error ", err
    quit(-1)
  #rd.echo0 "  disp0: ", toInt(disp0)
  #rd.echo0 "  datarep0: ", datarep0

  var subtype: MPI_Datatype
  err = MPI_Type_contiguous(cint elemsize, MPI_CHAR, addr subtype)
  err = MPI_Type_commit(addr subtype)

  var nd = cint lattice.len
  var lat = lattice.mapIt(cint it)
  var sublat = sublattice.mapIt(cint it)
  var offs = offsets.mapIt(cint it)
  var order = MPI_ORDER_FORTRAN
  var filetype: MPI_Datatype
  #rd.echo0 "lat: ", lat
  #rd.echo0 "sublat: ", sublat
  #rd.echo0 "offs: ", offs
  err = MPI_Type_create_subarray(nd, &lat, &sublat, &offs, order,
                                subtype, addr filetype)
  err = MPI_Type_commit(addr filetype)

  var info = MPI_INFO_NULL
  err = MPI_File_set_view(rd.fh, pos, MPI_CHAR, filetype, datarep0, info)
  if err != MPI_SUCCESS:
    echo "MPI_File_set_view failed with error ", err
    quit(-1)

  let nsites = sublat.foldl(a*b)
  let nbytes = nsites * elemsize
  #rd.echo0 "nsites: ", nsites
  #rd.echo0 "nbytes: ", nbytes
  var status: MPI_Status
  #err = MPI_File_read_all(rd.fh, buf, cint nbytes, MPI_CHAR, addr status)
  err = MPI_File_read_all(rd.fh, buf, cint nsites, subtype, addr status)
  if err != MPI_SUCCESS:
    echo "MPI_File_read_all failed with error ", err
    quit(-1)
  var nread: MPI_Count
  err = MPI_Get_elements_x(addr status, MPI_CHAR, addr nread)
  result = toInt(nread)

  err = MPI_File_set_view(rd.fh, disp0, etype0, filetype0, datarep0, info)
  discard MPI_Type_free(addr filetype)
  discard MPI_Type_free(addr subtype)

## Writer

type
  # create only, trunc only, create+trunc, append
  WriteMode* = enum
    wmCreate, wmTruncate, wmCreateOrTruncate, wmAppend
  Writer* = ref object
    filename*: string
    isOpen*: bool
    comm*: MPI_Comm
    fh*: MPI_File
    nranks*: int
    myrank*: int
    weInitedMpi*: bool

template echo0*(wr: Writer, args: varargs[untyped]) =
  if wr.myrank == 0:
    echo args

proc `xor`*(wr: Writer, x: var uint64) =
  var y = x
  let send = cast[pointer](addr y)
  let recv = cast[pointer](addr x)
  let err = MPI_Allreduce(send, recv, 1, MPI_UNSIGNED_LONG_LONG, MPI_BXOR, wr.comm)

proc open(wr: var Writer, wm: WriteMode) =
  if wr.isOpen:
    return
  var amode = MPI_MODE_WRONLY
  case wm
  of wmCreate: amode += MPI_MODE_CREATE + MPI_MODE_EXCL
  of wmTruncate: discard
  of wmCreateOrTruncate: amode += MPI_MODE_CREATE
  of wmAppend: amode += MPI_MODE_APPEND
  let info = MPI_INFO_NULL
  var err = MPI_File_open(wr.comm, wr.filename.cstring, amode, info, addr wr.fh)
  if err != MPI_SUCCESS:
    echo "open failed with error ", err
    quit(-1)
  err = MPI_File_set_size(wr.fh, 0)
  if err != MPI_SUCCESS:
    echo "open failed with error ", err
    quit(-1)
  wr.isOpen = true

proc newWriter*(fn: string, wm = wmCreateOrTruncate): Writer =
  result.new
  var inited = 0'i32
  var err = MPI_Initialized(addr inited)
  if inited == 0:
    err = MPI_Init()
    result.weInitedMpi = true
  result.filename = fn
  result.isOpen = false
  result.comm = MPI_COMM_WORLD
  var size, rank: cint
  err = MPI_Comm_size(result.comm, addr size)
  err = MPI_Comm_rank(result.comm, addr rank)
  result.nranks = size
  result.myrank = rank
  open result, wm

proc close*(wr: var Writer) =
  if wr.isOpen:
    wr.isOpen = false
    discard MPI_File_close(addr wr.fh)
    if wr.weInitedMpi:
      var err = MPI_Finalize()

proc seekTo*(wr: var Writer, offset: int) =
  var err = MPI_File_seek(wr.fh, offset, MPI_SEEK_SET)
  #rd.echoAll "seekTo: ", offset, "  err: ", err

proc write*(wr: var Writer, buf: pointer, nbytes: int): int =
  if not wr.isOpen:
    echo "ERROR: Writer write: not open"
    quit(-1)
  var status: MPI_Status
  var err = MPI_File_write_all(wr.fh, buf, nbytes.cint, MPI_CHAR, addr status)
  if err != MPI_SUCCESS:
    echo "pio write MPI_File_write_all err: ", err
  var nwrite: MPI_Count
  err = MPI_Get_elements_x(addr status, MPI_CHAR, addr nwrite)
  if err != MPI_SUCCESS:
    echo "pio write MPI_Get_count err: ", err
  result = toInt(nwrite)
template write*(wr: var Writer, buf: ptr typed, nbytes: SomeInteger): int =
  wr.write(cast[pointer](buf), int(nbytes))

proc write*(wr: var Writer, val: SomeNumber): int =
  let buf = unsafeaddr val
  let nbytes = sizeof(val)
  wr.write(buf, nbytes)

proc write*(wr: var Writer, val: string): int =
  let buf = unsafeaddr val[0]
  let nbytes = val.len
  wr.write(buf, nbytes)

proc write*(wr: var Writer; buf: pointer; elemsize: int;
            lattice,sublattice,offsets: seq[int]): int =
  #wr.echo0 "pio write"
  var pos: MPI_Offset
  var err = MPI_File_get_position(wr.fh, addr pos)
  if err != MPI_SUCCESS:
    echo "MPI_File_get_position failed with error ", err
    quit(-1)
  #wr.echo0 "  pos: ", toInt(pos)

  var disp0: MPI_Offset
  var etype0: MPI_Datatype
  var filetype0: MPI_Datatype
  var datarep0 = newString(MPI_MAX_DATAREP_STRING)
  err = MPI_File_get_view(wr.fh, addr disp0, addr etype0,
                          addr filetype0, datarep0)
  #wr.echo0 "  disp0: ", toInt(disp0)

  var subtype: MPI_Datatype
  err = MPI_Type_contiguous(cint elemsize, MPI_CHAR, addr subtype)
  err = MPI_Type_commit(addr subtype)

  var nd = cint lattice.len
  var lat = lattice.mapIt(cint it)
  var sublat = sublattice.mapIt(cint it)
  var offs = offsets.mapIt(cint it)
  var order = MPI_ORDER_FORTRAN
  var filetype: MPI_Datatype
  #wr.echo0 "lat: ", lat
  #wr.echo0 "sublat: ", sublat
  #wr.echo0 "offs: ", offs
  err = MPI_Type_create_subarray(nd, &lat, &sublat, &offs, order,
                                subtype, addr filetype)
  err = MPI_Type_commit(addr filetype)

  var info = MPI_INFO_NULL
  err = MPI_File_set_view(wr.fh, pos, MPI_CHAR, filetype, datarep0, info)
  if err != MPI_SUCCESS:
    echo "MPI_File_set_view failed with error ", err
    quit(-1)

  let nsites = sublat.foldl(a*b)
  let nbytes = nsites * elemsize
  #wr.echo0 "nsites: ", nsites
  #wr.echo0 "nbytes: ", nbytes
  var status: MPI_Status
  #err = MPI_File_write_all(wr.fh, buf, cint nbytes, MPI_CHAR, addr status)
  err = MPI_File_write_all(wr.fh, buf, cint nsites, subtype, addr status)
  if err != MPI_SUCCESS:
    echo "MPI_File_write_all failed with error ", err
    quit(-1)
  var nwrite: MPI_Count
  err = MPI_Get_elements_x(addr status, MPI_CHAR, addr nwrite)
  result = toInt(nwrite)

  err = MPI_File_set_view(wr.fh, disp0, etype0, filetype0, datarep0, info)
  discard MPI_Type_free(addr filetype)
  discard MPI_Type_free(addr subtype)

when isMainModule:
  import os
  let nargs = paramCount()
  case nargs
  of 0:
    let fn = "testwriter.lime"
    var w = newWriter(fn)
    w.echo0 "Writing file: ", fn
    template writeString(s: string) =
      let n = s.len
      let n1 = w.write n
      if n1 != sizeof(n):
        echo "ERROR: short write ", n1, " expected ", sizeof(n)
      let n2 = w.write s
      if n2 != n:
        echo "ERROR: short write ", n2, " expected ", n
    let s1 = "testpio"
    writeString(s1)
    let s2 = "some data"
    writeString(s2)
    w.close
    w.echo0 "Done"
  of 1:
    let fn = paramStr(1)
    var r = newReader(fn)
    r.echo0 "Reading file: ", fn
    template getString(): untyped =
      var n = 0
      let n1 = r.read n
      if n1 != sizeof(n):
        echo "ERROR: short read ", n1, " expected ", sizeof(n)
      var s = newString(n)
      let n2 = r.read s
      if n2 != n:
        echo "ERROR: short read ", n2, " expected ", n
      s
    let s1 = getString()
    r.echo0 s1
    let s2 = getString()
    r.echo0 s2
    r.close
    r.echo0 "Done"
  else:
    echo "Requires zero or one file argument."
