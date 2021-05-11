## Crc32
## x4 and x8 versions adapted from
##  https://create.stephan-brumme.com/crc32

import strutils
template `+=`[T](p: var ptr UncheckedArray[T], n: int) =
  p = cast[ptr UncheckedArray[T]](addr p[n])

type Crc32* = uint32
const InitCrc32* = Crc32(not 0'u32)
const crc32PolyLow = Crc32(0xedb88320)
const crc32Poly = uint64(0x100000000) + uint64(crc32PolyLow)

proc createCrcTable(): array[0..255, Crc32] =
  for i in 0..255:
    var rem = Crc32(i)
    for j in 0..7:
      if (rem and 1) > 0'u32: rem = (rem shr 1) xor crc32PolyLow
      else: rem = rem shr 1
    result[i] = rem

proc createCrcTable8(): array[8,array[256, Crc32]] =
  for i in 0..255:
    var rem = Crc32(i)
    for j in 0..7:
      if (rem and 1) > 0'u32: rem = (rem shr 1) xor crc32PolyLow
      else: rem = rem shr 1
    result[0][i] = rem
  for i in 0..255:
    result[1][i] = (result[0][i] shr 8) xor result[0][result[0][i] and 0xFF]
    result[2][i] = (result[1][i] shr 8) xor result[0][result[1][i] and 0xFF]
    result[3][i] = (result[2][i] shr 8) xor result[0][result[2][i] and 0xFF]
    result[4][i] = (result[3][i] shr 8) xor result[0][result[3][i] and 0xFF]
    result[5][i] = (result[4][i] shr 8) xor result[0][result[4][i] and 0xFF]
    result[6][i] = (result[5][i] shr 8) xor result[0][result[5][i] and 0xFF]
    result[7][i] = (result[6][i] shr 8) xor result[0][result[6][i] and 0xFF]

#const crc32table = createCrcTable()
const crc32table8 = createCrcTable8()
template crc32table: untyped = crc32table8[0]

proc updateCrc32(crc: Crc32, c: char): Crc32 {.inline.} =
  (crc shr 8) xor crc32table[(crc and 0xff) xor uint32(ord(c))]

proc updateCrc32x1(crc: Crc32, buf: pointer, nbytes: int): Crc32 {.inline.} =
  let cbuf = cast[ptr UncheckedArray[char]](buf)
  result = crc
  for i in 0..<nbytes:
    result = updateCrc32(result, cbuf[i])

# FIXME: little endian only
proc updateCrc32x4(crc: Crc32, buf: pointer, nbytes: int): Crc32 {.inline.} =
  result = crc
  var current = cast[ptr UncheckedArray[Crc32]](buf)
  var n = nbytes
  while n >= 4:
    result = result xor current[0]
    result = crc32table8[3][ result         and 0xFF] xor
             crc32table8[2][(result shr 8 ) and 0xFF] xor
             crc32table8[1][(result shr 16) and 0xFF] xor
             crc32table8[0][ result shr 24          ]
    current += 1
    n -= 4
  var currentChar = cast[ptr UncheckedArray[char]](current)
  while n > 0:
    result = (result shr 8) xor
             crc32table8[0][(result and 0xFF) xor Crc32(currentChar[0])]
    currentChar += 1
    n -= 1

# FIXME: little endian only
proc updateCrc32x8(crc: Crc32, buf: pointer, nbytes: int): Crc32 {.inline.} =
  result = crc
  var current = cast[ptr UncheckedArray[Crc32]](buf)
  var n = nbytes
  while n >= 8:
    let one = result xor current[0]
    let two = current[1]
    result = crc32table8[7][ one         and 0xFF] xor
             crc32table8[6][(one shr  8) and 0xFF] xor
             crc32table8[5][(one shr 16) and 0xFF] xor
             crc32table8[4][ one shr 24          ] xor
             crc32table8[3][ two         and 0xFF] xor
             crc32table8[2][(two shr  8) and 0xFF] xor
             crc32table8[1][(two shr 16) and 0xFF] xor
             crc32table8[0][ two shr 24          ]
    current += 2
    n -= 8
  var currentChar = cast[ptr UncheckedArray[char]](current)
  while n > 0:
    result = (result shr 8) xor
             crc32table8[0][(result and 0xFF) xor Crc32(currentChar[0])]
    currentChar += 1
    n -= 1

template updateCrc32(crc: Crc32, buf: pointer, nbytes: int): Crc32 =
  #updateCrc32x1(crc, buf, nbytes)
  #updateCrc32x4(crc, buf, nbytes)
  updateCrc32x8(crc, buf, nbytes)

proc finishCrc32*(c: Crc32): Crc32 {.inline.} =
  not c

proc crc32Raw*(buf: pointer, nbytes: int, init=InitCrc32): Crc32 =
  result = updateCrc32(init, buf, nbytes)

proc crc32Raw*(s: string, init=InitCrc32): Crc32 =
  let buf = cast[pointer](unsafeaddr s[0])
  let nbytes = s.len
  result = updateCrc32(init, buf, nbytes)

proc crc32*(buf: pointer, nbytes: int): Crc32 =
  result = updateCrc32(InitCrc32, buf, nbytes)
  result = finishCrc32(result)

proc crc32*(s: string): Crc32 =
  ## Compute the Crc32 on the string `s`
  let buf = cast[pointer](unsafeaddr s[0])
  let nbytes = s.len
  result = updateCrc32(InitCrc32, buf, nbytes)
  result = finishCrc32(result)

proc polyMul(x0: uint32, y0: uint64): uint64 =
  var x = x0
  var y = y0
  #echo x.toHex, "  ", y.toHex
  while x!=0:
    if (x and 1)!=0:
      result = result xor y
    #echo x.toHex, "  ", result.toHex
    y = y shl 1
    x = x shr 1

proc polyRem(x0: uint64, y0: uint64): uint32 =
  var x = x0
  var y = y0
  var b = 1.uint32
  var q = 0.uint32
  while (y and 0x8000000000000000'u64) == 0:
    y = y shl 1
    b = b shl 1
  while b != 0:
    #echo b, "  ", x, "  ", y
    if (x xor y) < x:
      x = x xor y
      q = q xor b
    y = y shr 1
    b = b shr 1
  echo q.toHex
  echo (x0 xor polyMul(q, y0)).toHex
  echo x.toHex
  result = x.uint32

proc mulRem(r1,r2: Crc32): Crc32 =
  var t = polyMul(r1, r2) shl 1
  for i in 0..<4:
    result = updateCrc32(result, char(t and 255))
    t = t shr 8
  result = result xor Crc32(t)

proc zeroPadCrc32X(crc: Crc32, n: int): Crc32 =
  var fac = Crc32(0x80000000)
  for i in 0..<n:
    fac = updateCrc32(fac, '\0')
  #echo "fac: ", fac.toHex
  result = mulRem(fac, crc)

proc zeroPadCrc32*(crc: Crc32, n: int): Crc32 =
  var fac = Crc32(0x80000000)
  var s = Crc32(0x00800000)
  var nn = n
  while nn > 0:
    if (nn and 1) != 0:
      fac = mulRem(fac, s)
    s = mulRem(s, s)
    nn = nn shr 1
  #echo "fac: ", fac.toHex
  result = mulRem(fac, crc)

when isMainModule:
  echo "initCrc32 = ", $InitCrc32
  let s = "The quick brown fox jumps over the lazy dog"
  let foo = crc32(s)
  echo foo
  doAssert(foo == 0x414FA339)

  for i in 0..<100:
    doAssert(zeroPadCrc32(1,i) == zeroPadCrc32X(1,i))

  var n = s.len
  var n2 = n div 2
  var s1 = s[0..<n2]
  var s2 = s[n2..<n]
  let foo1x = crc32Raw(s1, InitCrc32)
  let foo1 = zeroPadCrc32(foo1x, n-n2)
  let foo2 = crc32Raw(s2, 0)
  let foo12 = finishCrc32(foo1 xor foo2)
  doAssert(foo12 == foo)

  var f = newSeq[Crc32](n)
  f[0] = InitCrc32
  for i in 0..<n:
    f[i] = crc32Raw(s[i..i], f[i])
    let m = n-1-i
    for j in 0..<m:
      f[i] = zeroPadCrc32(f[i], 1)
  var ff = Crc32(0)
  for i in 0..<n:
    ff = ff xor f[i]
  ff = finishCrc32(ff)
  doAssert(ff == foo)
