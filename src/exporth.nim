import macros, strutils

type
  ExportH* = object
    hdr: string
    last: string
  Const*[T] = T

proc newExportH*(): ExportH =
  result.hdr = "#include <stddef.h>\n"  # for size_t
  result.hdr &= "#ifdef __cplusplus\n  extern \"C\" {\n#endif\n"
  result.last = "\n#ifdef __cplusplus\n}\n#endif\n"

proc writeS*(eh: ExportH, filename: string) =
  let fn = filename.toUpperAscii.replace('.','_')
  let fm = "__INCLUDED_" & fn & "__"
  var h = "#ifndef " & fm & "\n"
  h &= "#define " & fm & "\n"
  var f = "#endif /* " & fm & "*/\n"
  let s = h & eh.hdr & eh.last & f
  #echo s
  writeFile(filename, s)

template write*(eh: static ExportH, filename: static string) =
  static: writeS(eh, filename)

proc getIdent(x: NimNode): NimNode =
  case x.kind
  of nnkIdent,nnkSym:
    result = x
  of nnkPostfix:
    if x[0].kind == nnkIdent and $x[0] == "*":
      result = x[1]
    else:
      echo "getIdent: unknown nnkPostfix: ", x[0].treerepr
  else:
    echo "getIdent: unknown: ", x.treerepr

proc getLitStr(x: NimNode): string =
  case x.kind
  of nnkCharLit..nnkUInt64Lit:
    result = $x.intVal
  of nnkPrefix:
    result = $x[0] & $x[1].intVal
  else:
    echo "getLitStr: unknown lit kind: ", x.treerepr

proc cType(x: NimNode, id: string): string

proc cParam(x: NimNode): string =
  let id = $x[0].getIdent
  result = cType(x[1], id)

proc getProcArgs(params: NimNode): string =
  result = "("
  case params.len
  of 1:
    result &= "void"
  of 2:
    result &= params[1].cParam
  else:
    result &= params[1].cParam
    for i in 2..<params.len:
      result &= ", " & params[i].cParam
  result &= ")"

proc cType(x: NimNode, id: string): string =
  case x.kind
  of nnkEmpty:
    result = "void " & id
  of nnkIdent,nnkSym:
    case $x
    of "int32","cint": result = "int " & id
    of "int","int64": result = "long " & id
    of "uint32": result = "unsigned int " & id
    of "csize","csize_t": result = "size_t " & id
    of "pointer": result = "void *" & id
    of "cstring": result = "char *" & id
    of "cstringArray": result = "char *(" & id & "[])"
    else:
      #echo "cType: unknown ident: ", x.treerepr
      result = $x & " " & id
  of nnkPtrTy:
    result = cType(x[0], "*"&id)
  of nnkProcTy:
    result = cType(x[0][0], "(*"&id&")")
    result &= getProcArgs(x[0])
  of nnkBracketExpr:
    case $x[0]
    of "Const":
      result = cType(x[1], "const "&id)
    of "UncheckedArray":
      #if id.startsWith("*"):
      #  let t = id[1..^1] & "[]"
      #  result = cType(x[1], t)
      #else:
      result = cType(x[1], id)
    else:
      echo "cType: unknown nnkBracketExpr: ", x.treerepr
  else:
    echo "cType: unknown kind: ", x.treerepr

proc exporthCommentStmt(eh: var ExportH, x: NimNode): NimNode =
  eh.hdr &= "/* " & x.strVal & " */\n"
  result = x

template newConstDef(id,lit:untyped): untyped =
  const id {.exportc.} = lit
proc exporthConstDef(eh: var ExportH, x: NimNode): NimNode =
  let id = x[0]
  let lit = x[2]
  let litstr = getLitStr lit
  #eh.hdr &= "int " & $getIdent(id) & " = " & litstr & ";\n"
  eh.hdr &= "#define " & $getIdent(id) & " " & litstr & "\n"
  result = getAst(newConstDef(id,lit))[0]

template newTypeDef(id,def:untyped): untyped =
  type id {.exportc.} = def
proc exporthTypeDef(eh: var ExportH, x: NimNode): NimNode =
  #echo x.treerepr
  let id = x[0]
  let def = x[2]
  case def.kind
  of nnkObjectTy:
    let reclist = def[2]
    var s = "typedef struct {\n"
    for i in 0..<reclist.len:
      s &= "  " & cParam(reclist[i]) & ";\n"
    s &= "} " & $getIdent(id) & ";\n"
    #echo s
    eh.hdr &= s
  of nnkProcTy:
    var s = "typedef "
    s &= cType(def[0][0], "(*" & $getIdent(id) & ")")
    s &= getProcArgs(def[0])
    s &= ";\n"
    eh.hdr &= s
  else:
    echo "exporthTypeDef: unknown kind: ", def.treerepr
  result = getAst(newTypeDef(id,def))[0]
  #echo result.treerepr

template newProcDef(id:untyped): untyped =
  proc id {.exportc,dynlib.} = discard
proc exporthProcDef(eh: var ExportH, x: NimNode): NimNode =
  #echo x.treerepr
  let id = x[0]
  let params = x[3]
  let body = x[6]
  var s = cType(params[0], $getIdent(id))
  s &= getProcArgs(params)
  s &= ";\n"
  eh.hdr &= s
  result = getAst(newProcDef(id))
  result[3] = params
  result[6] = body
  #echo result.treerepr

proc exporthImpl(eh: var ExportH, x: NimNode): NimNode =
  case x.kind
  of nnkCommentStmt:
    result = exporthCommentStmt(eh, x)
  of nnkStmtList:
    result = newNimNode(nnkStmtList)
    for i in 0..<x.len:
      result.add exporthImpl(eh, x[i])
  of nnkConstSection:
    #echo x.repr
    result = newNimNode(nnkConstSection)
    for i in 0..<x.len:
      case x[i].kind
      of nnkConstDef:
        result.add exporthConstDef(eh, x[i])
      of nnkCommentStmt:
        result.add exporthCommentStmt(eh, x[i])
      else:
        echo "exporthImpl: unknown kind: ", x[i].treerepr
  of nnkTypeSection:
    result = newNimNode(nnkTypeSection)
    for i in 0..<x.len:
      if x[i].kind==nnkTypeDef:
        result.add exporthTypeDef(eh, x[i])
  of nnkProcDef:
    result = exporthProcDef(eh, x)
  of nnkTemplateDef:
    result = x
  else:
    result = x
    echo "exporthImpl unknown kind: ", x.kind

macro add*(eh: static var ExportH, x: untyped): untyped =
  if x.kind == nnkStrLit:
    eh.hdr &= x.strVal
  else:
    if eh.hdr != "": eh.hdr.add "\n"
    #echo x.treerepr
    #result = x
    #if x.kind==nnkStmtList and x.len==1:
    #  result = exporthImpl(x[0])
    #else:
    result = exporthImpl(eh, x)
    #echo result.treerepr
    #echo result.repr
