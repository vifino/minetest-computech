-- ZPU Emulator: EMULATE speedups
-- Used to avoid needing crt0.S and co.

-- Pass in the ZPU, and it will implement some EMULATE opcodes.

-- Right now, 6 implemented operations are untested.
-- ULESSTHAN, EQBRANCH, 

-- Licence:
-- I, gamemanj, release this code into the public domain.
-- I make no guarantees or provide any warranty,
--  implied or otherwise, with this code.

-- Debug config --
-- For figuring out if there's something horribly wrong with the testcase
local usage_trace = false

-- Globals --

local args = {...}
local zpu = args[1]
local emulates = {}
local unused_emulates = 0 -- this is incremented when emulates are added and usage_trace is set

-- utils --
local bitAnd = zpu.bitAnd
local bitOr = zpu.bitOr
local bitXor = zpu.bitXor
local bitShl = zpu.bitShl
local bitShr = zpu.bitShr

local function a32(v)
 return bitAnd(v, 0xFFFFFFFF)
end
local function sflip(v)
 v = a32(v)
 if bitAnd(v, 0x80000000) ~= 0 then
  return v - 0x100000000
 end
 return v
end
local function mkbool(v)
 if v then return 1 else return 0 end
end
local function advip()
 zpu.rIP = a32(zpu.rIP + 1)
end

-- getb and setb are the internal implementation of LOADB and STOREB,
-- and are thus heavily endianness-dependent.
local function getb(a)
 local s = (24 - bitShl(bitAnd(a, 3), 3))
 local av = zpu.get32(bitAnd(a, 0xFFFFFFFC))
 return bitAnd(bitShr(av, s), 0xFF)
end

local function setb(a, v)
 local s = (24 - bitShl(bitAnd(a, 3), 3))
 local b = bitXor(bitShl(0xFF, s), 0xFFFFFFFF)
 local av = zpu.get32(bitAnd(a, 0xFFFFFFFC))
 av = bitAnd(av, b)
 av = bitOr(av, bitShl(bitAnd(v, 0xFF), s))
 zpu.set32(bitAnd(a, 0xFFFFFFFC), av)
end

-- geth and seth are the same but for halfwords.
-- This implementation will just mess up if it gets a certain kind of misalignment.
-- (I have no better ideas - there is no reliable way to error-escape.)

local function geth(a)
 local s = (24 - bitShl(bitAnd(a, 3), 3))
 local av = zpu.get32(bitAnd(a, 0xFFFFFFFC))
 return bitAnd(bitShr(av, s), 0xFFFF)
end

local function seth(a, v)
 local s = (24 - bitShl(bitAnd(a, 3), 3))
 local b = bitXor(bitShl(0xFFFF, s), 0xFFFFFFFF)
 local av = zpu.get32(bitAnd(a, 0xFFFFFFFC))
 av = bitAnd(av, b)
 av = bitOr(av, bitShl(bitAnd(v, 0xFFFF), s))
 zpu.set32(bitAnd(a, 0xFFFFFFFC), av)
end

local function eqbranch(bcf)
 local br = zpu.rIP + zpu.v_pop()
 local cond = bcf(zpu.v_pop())
 if cond then
  zpu.rIP = br
 else
  advip()
 end
end

-- Generic left/right shifter, logical-only.
local function gpi_shift(v, lShift)
 if lShift >= 32 then return 0 end
 if lShift > 0 then return bitShl(v, lShift) end
 if lShift <= -32 then return 0 end
 if lShift < 0 then return bitShr(v, -lShift) end
 return 0
end
-- Generic multifunction shifter. Should handle any case with ease.
local function gp_shift(v, lShift, arithmetic)
 -- "arithmetic" flag only matters for negative values.
 arithmetic = arithmetic and bitAnd(v, 0x80000000) ~= 0
 v = gpi_shift(v, lShift)
 if arithmetic and (lShift < 0) then
  -- to explain: the "mask" is the bits that are defined in v post-operation.
  -- Invert that, then OR, and you get right-shift sign extension.
  local mask = gpi_shift(0xFFFFFFFF, lShift)
  v = bitOr(v, bitXor(mask, 0xFFFFFFFF))
 end
 return v
end

-- builders --

local function make_emu(id, name, code)
 local unused = true
 if usage_trace then
  emulates[id] = {name, function (...)
   if unused then
    unused = false
    io.stderr:write(name .. " used, " .. unused_emulates .. " to go\n") 
    unused_emulates = unused_emulates - 1
   end
   return code(...)
  end}
 else
  emulates[id] = {name, code}
 end
 unused_emulates = unused_emulates + 1
end
local function make_pair(id, name, code)
 make_emu(id, name, function ()
  local a = zpu.v_pop()
  local b = zpu.get32(zpu.rSP)
  zpu.set32(zpu.rSP, code(a, b))
  advip()
 end)
end
local function make_opair(id, name, code)
 make_emu(id, name, function ()
  local a = zpu.v_pop()
  local b = zpu.get32(zpu.rSP)
  zpu.set32(zpu.rSP, code(b, a))
  advip()
 end)
end

-- The Actual Emulates --

make_emu(19, "LOADH", function () zpu.set32(zpu.rSP, geth(zpu.get32(zpu.rSP))) advip() end)
make_emu(20, "STOREH", function ()
 local a = zpu.v_pop()
 local v = zpu.v_pop()
 seth(a, v)
 advip()
end)

make_pair(4, "LESSTHAN", function (a, b) return mkbool(sflip(a) < sflip(b)) end)
make_pair(5, "LESSTHANEQUAL", function (a, b) return mkbool(sflip(a) <= sflip(b)) end)
make_pair(6, "ULESSTHAN", function (a, b) return mkbool(a < b) end)
make_pair(7, "ULESSTHANEQUAL", function (a, b) return mkbool(a <= b) end)

make_pair(9, "SLOWMULT", function (a, b) return bitAnd(a * b, 0xFFFFFFFF) end)

-- For now, it is assumed that signed shifts are OK.
-- If not, remove the sflip(a) converter.
make_pair(10, "LSHIFTRIGHT", function (a, b)
 return gp_shift(b, -sflip(a), false)
end)
make_pair(11, "ASHIFTLEFT", function (a, b)
 return gp_shift(b, sflip(a), true)
end)
make_pair(12, "ASHIFTRIGHT", function (a, b)
 return gp_shift(b, -sflip(a), true)
end)

make_pair(14, "EQ", function (a, b) return mkbool(a == b) end)
make_pair(15, "NEQ", function (a, b) return mkbool(a ~= b) end)

make_emu(16, "NEQ", function ()
 local v = zpu.get32(zpu.rSP)
 -- negate is implemented in C via some complex method guaranteed to work,
 -- but does anyone actually care?
 v = a32(-sflip(v))
 zpu.set32(zpu.rSP, v)
 advip()
end)

make_opair(17, "SUB", function (a, b) return bitAnd(a - b, 0xFFFFFFFF) end)
make_opair(18, "XOR", function (a, b) return bitAnd(bitXor(a, b), 0xFFFFFFFF) end)

make_emu(19, "LOADB", function () zpu.set32(zpu.rSP, getb(zpu.get32(zpu.rSP))) advip() end)
make_emu(20, "STOREB", function ()
 local a = zpu.v_pop()
 local v = zpu.v_pop()
 setb(a, v)
 advip()
end)

local function rtz(v)
 if v < 0 then return math.ceil(v) end
 return math.floor(v)
end
-- kind of weird, but it gets the job done
local function cmod(a, b)
 local r = rtz(a / b)
 local m = a - (r * b)
 return m
end
make_pair(21, "DIV", function (a, b) return a32(rtz(sflip(a) / sflip(b))) end)
make_pair(22, "MOD", function (a, b) return a32(cmod(sflip(a), sflip(b))) end)

make_emu(23, "EQBRANCH", function () eqbranch(function(b) return b == 0 end) end)
make_emu(24, "NEQBRANCH", function () eqbranch(function(b) return b ~= 0 end) end)

make_emu(25, "POPPCREL", function () zpu.rIP = bitAnd(zpu.rIP + zpu.v_pop(), 0xFFFFFFFF) end)

make_emu(29, "PUSHSPADD", function ()
 local newP = bitAnd(bitAnd(bitShl(zpu.get32(zpu.rSP), 2), 0xFFFFFFFF) + zpu.rSP, 0xFFFFFFFC)
 zpu.set32(zpu.rSP, newP)
 advip()
end)

make_emu(31, "CALLPCREL", function ()
 local routine = bitAnd(zpu.rIP + zpu.get32(zpu.rSP), 0xFFFFFFFF)
 zpu.set32(zpu.rSP, bitAnd(zpu.rIP + 1, 0xFFFFFFFF))
 zpu.rIP = routine
end)

-- The final code --

local emu = zpu.op_emulate
function zpu.op_emulate(op)
 if emulates[op] then
  emulates[op][2]()
  return emulates[op][1]
 end
 if usage_trace then io.stderr:write("zpu_emus.lua: usage trace found " .. op .. " hasn't been written yet.") end
 return emu(op)
end