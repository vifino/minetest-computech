-- bit32 emulation.

-- Licence:
-- I, 20kdc, release this code into the public domain.
-- I make no guarantees or provide any warranty,
--  implied or otherwise, with this code.

-- Not entirely accurate, but less buggy than the implementations it has to work around.

-- For absolutely strict mode, enable this
-- (it will use the slower emulation routines, which do more checking on shifts/etc
--  and throw errors if unexpected stuff is likely to happen)
local strict = false

local ourBit32 = {}

local bit32 = bit32 or bit
if not bit32 then
 pcall(function ()
  bit32 = require("bit32")
 end)
end

-- REMEMBER THIS IS ALL IN THE PUBLIC DOMAIN.
-- If you want to steal my routines without attribution, just do so.
-- If I catch someone who knows about these reimplementing for any reason other than performance,
-- (because they ARE slow)
--  I'll shout at them a bit!

local function bitConv(na, nb, f)
 na = math.floor(na)
 nb = math.floor(nb)
 -- Fixup negative values before beginning, just in case
 while na < 0 do
  na = na + 0x100000000
 end
 while nb < 0 do
  nb = nb + 0x100000000
 end
 local r = 0
 local p = 1
 for i = 1, 32 do
  local pa = na / 2
  local pb = nb / 2
  na = math.floor(pa)
  nb = math.floor(pb)
  if f(pa ~= na, pb ~= nb) then
   r = r + p
  end
  p = p * 2
 end
 return r
end

local function getBitOp(lua52, b32, testpoint, emergency)
 -- Neither method seems to be faster,
 -- and either way speed has been hurt by the "no direct bitops" workarounds.
 -- As it is, the "emergency" method is the slowest, but you knew that already.
 if (not strict) and bit32 then
  if bit32[b32] then
   if bit32[b32](5, 4) == testpoint then
    return bit32[b32]
   --else
   -- io.stderr:write("Native function " .. b32 .. " was bad, using fallback\n")
   end
  end
 end
 local rvf = loadstring("return function (a, b) return a " .. lua52 .. " b end")
 if strict then rvf = nil end
 if not rvf then
  local r = function (a, b) return emergency(a, b) end
  if r(5, 4) ~= testpoint then error("internal emergency-bitops test failure " .. b32) end
  return r
 end
 return rvf()
end

local bitAnd = getBitOp("&", "band", 4, function (a, b)
 -- This is often used where the situation warrants a reconvert back to bit32.
 -- So, don't assume it will receive sane input.

 -- However, there are a lot of cases where the "convert to bit32" behavior is used.
 -- Which are currently rather slow in the "no need to convert" case.
 -- These neatly cover a good portion of these "there was no need to do this" cases,
 --  speeds things up enormously.

 if (b == 0xFFFFFFFF) and (a >= 0) and (a <= 0xFFFFFFFF) then return math.floor(a) end
 if (a == 0xFFFFFFFF) and (b >= 0) and (b <= 0xFFFFFFFF) then return math.floor(b) end
 if (b == 0xFFFFFFFF) and (a < 0) then
  a = math.floor(0x100000000 + a)
  if (a >= 0) and (a <= 0xFFFFFFFF) then return a end
 end
 if (a == 0xFFFFFFFF) and (b < 0) then
  b = math.floor(0x100000000 + b)
  if (b >= 0) and (b <= 0xFFFFFFFF) then return b end
 end

 return bitConv(a, b, function (a, b) return a and b end)
end)
-- Most of these don't go through sanity checks - and32 is used as the "ensure bit32" function.
local bitOr = getBitOp("|", "bor", 5, function (a, b)
 return bitConv(a, b, function (a, b) return a or b end)
end)
local bitXor = getBitOp("~", "bxor", 1, function (a, b)
 -- believe it or not, even boolean XOR is not available
 return bitConv(a, b, function (a, b) return (a or b) and (not (a and b)) end)
end)
-- NOTE: These are considered to be logical shifts.
local bitShl = getBitOp("<<", "lshift", 80, function (a, b)
 if b < 0 then error("bad shift") end
 if a < 0 then error("bad input") end
 if b >= 32 then return 0 end
 while b > 0 do
  local s = b
  -- prevent potential bad things due to floating point
  if s > 14 then s = 14 end
  
  a = math.floor(a * (2 ^ s))
  a = a - (math.floor(a / 0x100000000) * 0x100000000)
  b = b - s
 end
 return a
end)
local bitShr = getBitOp(">>", "rshift", 0, function (a, b)
 if b < 0 then error("bad shift") end
 if a < 0 then error("bad input") end
 return math.floor(a / (2 ^ b))
end)

if bitShl(0x80000000, 1) == 0x100000000 then
 --io.stderr:write("bitShl could return >32 bits, workaround in place.\n")
 local bitShlBackup = bitShl
 bitShl = function (v, s)
  return bitAnd(bitShlBackup(v, s), 0xFFFFFFFF)
 end
end

if bitShl(1, 32) == 1 then
 --io.stderr:write("bitShl will wrap at 32 (assuming same for bitShr)\n")
 local bitShlBackup = bitShl
 bitShl = function (v, s)
  if s > 31 then return 0 end
  return bitShlBackup(v, s)
 end
 local bitShrBackup = bitShr
 bitShr = function (v, s)
  if s > 31 then return 0 end
  return bitShrBackup(v, s)
 end
end

if bitShr(0x80000000, 24) ~= 128 then
 --io.stderr:write("bitShr was arithmetic, this is really bad! Still, this is known now - speed gains can still be gotten.")
 local bitShrBackup = bitShr
 bitShr = function (v, s)
  local mask = 0xFFFFFFFF
  return bitAnd(bitShrBackup(v, s), bitShrBackup(mask, s))
 end
end

-- LuaJIT: Reimplementing Lua APIs, badly.
if bitAnd(-1, -2) == -2 then
 --io.stderr:write("Logic functions are SIGNED (not unsigned) 32-bit. Seriously. You're probably using LuaJIT.\n")
 local function fixNegVal(i)
  local j = i
  -- clean up value, and throw it through.
  while i < 0 do
   i = i + 0x100000000
  end
  return i
 end
 local function fixNegValWrap(f)
  return function (a, b)
   local v = f(fixNegVal(a), fixNegVal(b))
   return fixNegVal(v)
  end
 end
 bitAnd = fixNegValWrap(bitAnd)
 bitOr = fixNegValWrap(bitOr)
 bitXor = fixNegValWrap(bitXor)
 -- These shouldn't get negative values in shift
 -- (it deliberately errors in zero-primitive mode if they do)
 bitShl = fixNegValWrap(bitShl)
 bitShr = fixNegValWrap(bitShr)
end

ourBit32.band = bitAnd
ourBit32.bor = bitOr
ourBit32.bxor = bitXor
ourBit32.lshift = bitShl
ourBit32.rshift = bitShr

return ourBit32