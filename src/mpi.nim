{. pragma: mpih, importc, header: "mpi.h" .}

type
  MPI_Comm* {.mpih.} = object
  MPI_Count* {.mpih.} = object
  MPI_Datatype* {.mpih.} = object
  MPI_File* {.mpih.} = object
  MPI_Info* {.mpih.} = object
  MPI_Offset* {.mpih.} = object
  MPI_Op* {.mpih.} = object
  MPI_Status* {.mpih.} = object

var
  MPI_COMM_WORLD* {.mpih.}: MPI_Comm

  MPI_CHAR* {.mpih.}: MPI_Datatype
  MPI_INT* {.mpih.}: MPI_Datatype
  MPI_LONG* {.mpih.}: MPI_Datatype
  MPI_UNSIGNED_LONG* {.mpih.}: MPI_Datatype
  MPI_UNSIGNED_LONG_LONG* {.mpih.}: MPI_Datatype
  MPI_FLOAT* {.mpih.}: MPI_Datatype
  MPI_DOUBLE* {.mpih.}: MPI_Datatype

  MPI_BXOR* {.mpih.}: MPI_Op

  MPI_MODE_CREATE* {.mpih.}: cint
  MPI_MODE_RDONLY* {.mpih.}: cint
  MPI_MODE_WRONLY* {.mpih.}: cint

  MPI_SEEK_SET* {.mpih.}: cint

  MPI_INFO_NULL* {.mpih.}: MPI_Info
  MPI_MAX_INFO_KEY* {.mpih.}: cint
  MPI_MAX_INFO_VAL* {.mpih.}: cint
  MPI_MAX_DATAREP_STRING* {.mpih.}: cint
  MPI_ORDER_FORTRAN* {.mpih.}: cint
  MPI_ORDER_C* {.mpih.}: cint

  MPI_SUCCESS* {.mpih.}: cint


proc MPI_Init*(argc: ptr cint; argv: ptr cstringArray): cint {.
  importc: "MPI_Init", header: "mpi.h".}
proc MPI_Initialized*(flag: ptr cint): cint {.
  importc: "MPI_Initialized", header: "mpi.h".}
proc MPI_Finalize*(): cint {.
  importc: "MPI_Finalize", header: "mpi.h".}

proc MPI_Comm_rank*(comm: MPI_Comm; rank: ptr cint): cint {.
  importc: "MPI_Comm_rank", header: "mpi.h".}
proc MPI_Comm_size*(comm: MPI_Comm; size: ptr cint): cint {.
  importc: "MPI_Comm_size", header: "mpi.h".}

proc MPI_Barrier*(comm: MPI_Comm): cint {.
  importc: "MPI_Barrier", header: "mpi.h".}

proc MPI_Allreduce*(sendbuf: pointer; recvbuf: pointer; count: cint;
                    datatype: MPI_Datatype; op: MPI_Op; comm: MPI_Comm): cint {.
  importc: "MPI_Allreduce", header: "mpi.h".}

proc MPI_File_open*(comm: MPI_Comm; filename: cstring; amode: cint;
                    info: MPI_Info; fh: ptr MPI_File): cint {.
  importc: "MPI_File_open", header: "mpi.h".}
proc MPI_File_close*(fh: ptr MPI_File): cint {.
  importc: "MPI_File_close", header: "mpi.h".}
proc MPI_File_get_size*(fh: MPI_File; size: ptr MPI_Offset): cint {.
    importc: "MPI_File_get_size", header: "mpi.h".}
proc MPI_File_set_size*(fh: MPI_File; size: MPI_Offset): cint {.
    importc: "MPI_File_set_size", header: "mpi.h".}
proc MPI_File_get_position*(fh: MPI_File; offset: ptr MPI_Offset): cint {.
    importc: "MPI_File_get_position", header: "mpi.h".}
proc MPI_File_get_info*(fh: MPI_File; info_used: ptr MPI_Info): cint {.
  importc: "MPI_File_get_info", header: "mpi.h".}
proc MPI_File_get_view*(fh: MPI_File; disp: ptr MPI_Offset;
                        etype: ptr MPI_Datatype; filetype: ptr MPI_Datatype;
                        datarep: cstring): cint {.
  importc: "MPI_File_get_view", header: "mpi.h".}
proc MPI_File_set_view*(fh: MPI_File; disp: MPI_Offset; etype: MPI_Datatype;
                    filetype: MPI_Datatype; datarep: cstring; info: MPI_Info): cint {.
  importc: "MPI_File_set_view", header: "mpi.h".}
proc MPI_File_seek*(fh: MPI_File; offset: MPI_Offset; whence: cint): cint {.
    importc: "MPI_File_seek", header: "mpi.h".}
proc MPI_File_read*(fh: MPI_File; buf: pointer; count: cint;
                    datatype: MPI_Datatype; status: ptr MPI_Status): cint {.
    importc: "MPI_File_read", header: "mpi.h".}
proc MPI_File_read_all*(fh: MPI_File; buf: pointer; count: cint;
                        datatype: MPI_Datatype; status: ptr MPI_Status): cint {.
    importc: "MPI_File_read_all", header: "mpi.h".}
proc MPI_File_write*(fh: MPI_File; buf: pointer; count: cint;
                     datatype: MPI_Datatype; status: ptr MPI_Status): cint {.
    importc: "MPI_File_write", header: "mpi.h".}
proc MPI_File_write_all*(fh: MPI_File; buf: pointer; count: cint;
                         datatype: MPI_Datatype; status: ptr MPI_Status): cint {.
    importc: "MPI_File_write_all", header: "mpi.h".}

proc MPI_Info_create*(info: ptr MPI_Info): cint {.
  importc: "MPI_Info_create", header: "mpi.h".}
proc MPI_Info_delete*(info: MPI_Info; key: cstring): cint {.
  importc: "MPI_Info_delete", header: "mpi.h".}
proc MPI_Info_dup*(info: MPI_Info; newinfo: ptr MPI_Info): cint {.
  importc: "MPI_Info_dup", header: "mpi.h".}
proc MPI_Info_free*(info: ptr MPI_Info): cint {.
  importc: "MPI_Info_free", header: "mpi.h".}
proc MPI_Info_get*(info: MPI_Info; key: cstring; valuelen: cint; value: cstring;
                   flag: ptr cint): cint {.
  importc: "MPI_Info_get", header: "mpi.h".}
proc MPI_Info_get_nkeys*(info: MPI_Info; nkeys: ptr cint): cint {.
  importc: "MPI_Info_get_nkeys", header: "mpi.h".}
proc MPI_Info_get_nthkey*(info: MPI_Info; n: cint; key: cstring): cint {.
  importc: "MPI_Info_get_nthkey", header: "mpi.h".}
proc MPI_Info_get_valuelen*(info: MPI_Info; key: cstring; valuelen: ptr cint;
                            flag: ptr cint): cint {.
  importc: "MPI_Info_get_valuelen", header: "mpi.h".}
proc MPI_Info_set*(info: MPI_Info; key: cstring; value: cstring): cint {.
  importc: "MPI_Info_set", header: "mpi.h".}

#proc MPI_Get_count*(status: ptr MPI_Status; datatype: MPI_Datatype;
#                    count: ptr cint): cint {.
#  importc: "MPI_Get_count", header: "mpi.h".}
proc MPI_Get_elements_x*(status: ptr MPI_Status; datatype: MPI_Datatype;
                         count: ptr MPI_Count): cint {.
    importc: "MPI_Get_elements_x", header: "mpi.h".}

proc MPI_Type_contiguous*(count: cint; oldtype: MPI_Datatype;
                          newtype: ptr MPI_Datatype): cint {.
  importc: "MPI_Type_contiguous", header: "mpi.h".}
proc MPI_Type_create_subarray*(ndims: cint; size_array: ptr cint;
                               subsize_array: ptr cint; start_array: ptr cint;
                               order: cint; oldtype: MPI_Datatype;
                               newtype: ptr MPI_Datatype): cint {.
  importc: "MPI_Type_create_subarray", header: "mpi.h".}
proc MPI_Type_commit*(`type`: ptr MPI_Datatype): cint {.
  importc: "MPI_Type_commit", header: "mpi.h".}
proc MPI_Type_free*(`type`: ptr MPI_Datatype): cint {.
  importc: "MPI_Type_free", header: "mpi.h".}


proc MPI_Init*(): cint =
  var argc {.importc: "cmdCount", global.}: cint
  var argv {.importc: "cmdLine", global.}: cstringArray
  var inited = 0'i32
  result = MPI_Initialized(addr inited)
  if inited == 0:
    result = MPI_Init(argc.addr, argv.addr)

converter toMpiCount*(x: int): MPI_Count =
  {.emit:[result," = ",x,";"].}
converter toInt*(x: MPI_Count): int =
  {.emit:[result," = ",x,";"].}

converter toMpiOffset*(x: int): MPI_Offset =
  {.emit:[result," = ",x,";"].}
converter toInt*(x: MPI_Offset): int =
  {.emit:[result," = ",x,";"].}
