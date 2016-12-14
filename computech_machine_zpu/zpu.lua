-- ZPU Emulator V2.1
-- It returns a ZPU emulator.
-- elements:
-- zpu.rSP: Stack pointer. You should set this to the top of memory.
-- zpu.rIP: Instruction pointer.
-- zpu.fLastIM: "Last opcode was IM" flag.
-- zpu.get32(i:addr)->i:val: You must set this before using the emulator.
--            Unaligned accesses do not happen.
-- zpu.set32(i:addr, i:val): You must set this before using the emulator.
--            Unaligned accesses do not happen.
-- zpu.op_emulate(i:op)->s:disassembly: Run one EMULATE opcode. (Can be overridden.)
-- zpu.run()->s:disassembly: Run one opcode. Returns nil if unknown.
-- zpu.run_trace(f:file, i:stackdump)->s:disassembly: Run one opcode,
--            giving an instruction & stack trace to the file.
-- zpu.v_pop/zpu.v_push: helper functions
-- zpu.bitAnd/zpu.bitOr/zpu.bitXor/zpu.bitShl/zpu.bitShr:
--  Completely 100% portable bitops, even on Lua 5.1 without bit32.
--  Some self-tests are done to ensure the validity of the bitops implementation being used.
--  Furthermore, if arithmetic rather than logical shifts are in place, workarounds are used.

-- Licence:
-- I, gamemanj, release this code into the public domain.
-- I make no guarantees or provide any warranty,
--  implied or otherwise, with this code.

-- Notes on emulator behavior:
-- Addresses are ANDed with 0xFFFFFFFC. Thus, unaligned accesses simply do not happen.

local zpu = {}

local bit32 = bit32 or bit
if not bit32 then
 pcall(function ()
  bit32 = require("bit32")
 end)
end

-- Workarounds for Lua versioning limitations.
-- In theory bit32 could be excised from the globalspace
--  (you never know with these PUC-Rio people, never mind the possibility of nasty environments)
-- and anyway this whole thing is enough of a mess that we may as well
-- keep our own copies just so that if we DO have to reroute, we have a way.

-- Also note: REMEMBER THIS IS ALL IN THE PUBLIC DOMAIN.
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

local getBitOpFallbacks = {}
local function getBitOp(lua52, b32, testpoint, emergency)
 getBitOpFallbacks[lua52] = emergency
 -- Neither method seems to be faster,
 -- and either way speed has been hurt by the "no direct bitops" workarounds.
 -- Hopefully zpu_emus should keep things acceptable.
 -- As it is, the "emergency" method is the slowest, but you knew that already.
 if bit32 then
  if bit32[b32] then
   if bit32[b32](5, 4) == testpoint then
    return bit32[b32]
   else
    io.stderr:write("zpu.lua: bit32." .. b32 .. " was bad, faulty bit32 in use.\n")
   end
  end
 end
 local rvf = loadstring("return function (a, b) return a " .. lua52 .. " b end")
 if not rvf then
  local r = function (a, b) return emergency(a, b) end
  if r(5, 4) ~= testpoint then error("zpu.lua: internal emergency-bitops test failure " .. b32) end
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
 io.stderr:write("zpu.lua: bitShl could return >32 bits, workaround in place.\n")
 local bitShlBackup = bitShl
 bitShl = function (v, s)
  return bitAnd(bitShlBackup(v, s), 0xFFFFFFFF)
 end
end

if bitShl(1, 32) == 1 then
 io.stderr:write("zpu.lua: bitShl will wrap at 32 (assuming same for bitShr)\n")
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
 io.stderr:write("zpu.lua: bitShr was arithmetic, this is really bad! Still, this is known now - speed gains can still be gotten.")
 local bitShrBackup = bitShr
 bitShr = function (v, s)
  local mask = 0xFFFFFFFF
  return bitAnd(bitShrBackup(v, s), bitShrBackup(mask, s))
 end
end

-- LuaJIT: Reimplementing Lua APIs, badly.
if bitAnd(-1, -2) == -2 then
 io.stderr:write("zpu.lua: Logic functions are SIGNED (not unsigned) 32-bit. Seriously. You're probably using LuaJIT.\n")
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

zpu.bitAnd = bitAnd
zpu.bitOr = bitOr
zpu.bitXor = bitXor
zpu.bitShl = bitShl
zpu.bitShr = bitShr

-- Begin the actual code.

zpu.rSP = 0
zpu.rIP = 0
zpu.fLastIM = false

-- Used for byte extraction by the opcode getter.
-- (This ZPU implementation does not implement even a 1-word instruction cache.)
local function split32(v)
 local d = {}
 d[1] = bitAnd(bitShr(v, 24), 0xFF)
 d[2] = bitAnd(bitShr(v, 16), 0xFF)
 d[3] = bitAnd(bitShr(v, 8), 0xFF)
 d[4] = bitAnd(v, 0xFF)
 return d
end

local function v_push(v)
 zpu.rSP = bitAnd(zpu.rSP - 4, 0xFFFFFFFF)
 zpu.set32(zpu.rSP, v)
end
zpu.v_push = v_push
local function v_pop()
 local v = zpu.get32(zpu.rSP)
 zpu.rSP = bitAnd(zpu.rSP + 4, 0xFFFFFFFC)
 return v
end
zpu.v_pop = v_pop

local function op_im(i, last)
 if last then
  v_push(bitOr(bitShl(bitAnd(v_pop(), 0x1FFFFFFF), 7), i))
 else
  if bitAnd(i, 0x40) ~= 0 then i = bitOr(i, 0xFFFFFF80) end
  v_push(i)
 end
end
local function op_loadsp(i)
 v_push(zpu.get32(bitAnd(zpu.rSP + bitShl(bitXor(i, 0x10), 2), 0xFFFFFFFC)))
end
local function op_storesp(i)
 -- Be careful with the ordering! Documentation suggests the OPPOSITE
 --  of what should be!
 -- https://github.com/zylin/zpugcc/blob/master/toolchain/gcc/libgloss/zpu/crt0.S#L836
 -- this is a good testpoint:
 -- 0x81 0x3F
 -- This should leave zpu.rSP + 4 on stack.
 -- Work it out from the sources linked.
 local bsp = bitAnd(zpu.rSP + bitShl(bitXor(i, 0x10), 2), 0xFFFFFFFC)
 zpu.set32(bsp, v_pop())
end
local function op_addsp(i)
 local addr = bitAnd(zpu.rSP + bitShl(i, 2), 0xFFFFFFFC)
 local a = v_pop()
 v_push(zpu.get32(addr) + a)
end
local function op_load()
 zpu.set32(zpu.rSP, zpu.get32(bitAnd(zpu.get32(zpu.rSP), 0xFFFFFFFC)))
end
local function op_store()
 local a = bitAnd(v_pop(), 0xFFFFFFFC)
 zpu.set32(a, v_pop())
end
local function op_add()
 local a = v_pop()
 zpu.set32(zpu.rSP, bitAnd(a + zpu.get32(zpu.rSP), 0xFFFFFFFF))
end
local function op_and()
 v_push(bitAnd(v_pop(), v_pop()))
end
local function op_or()
 v_push(bitOr(v_pop(), v_pop()))
end
local function op_not()
 v_push(bitXor(v_pop(), 0xFFFFFFFF))
end

local op_flip_tb = {}
op_flip_tb[0] = 0 op_flip_tb[1] = 2 op_flip_tb[2] = 1 op_flip_tb[3] = 3
local function op_flip_byte(i)
 local a = bitShr(bitAnd(i, 0xC0), 6)
 local b = bitShr(bitAnd(i, 0x30), 4)
 local c = bitShr(bitAnd(i, 0x0C), 2)
 local d = bitAnd(i, 0x03)
 a = op_flip_tb[a]
 b = op_flip_tb[b]
 c = op_flip_tb[c]
 d = op_flip_tb[d]
 return bitOr(bitOr(a, bitShl(b, 2)), bitOr(bitShl(c, 4), bitShl(d, 6)))
end
local function op_flip()
 local v = v_pop()
 local a = bitAnd(bitShr(v, 24), 0xFF)
 local b = bitAnd(bitShr(v, 16), 0xFF)
 local c = bitAnd(bitShr(v, 8), 0xFF)
 local d = bitAnd(v, 0xFF)
 a = op_flip_byte(a)
 b = op_flip_byte(b)
 c = op_flip_byte(c)
 d = op_flip_byte(d)
 v_push(bitOr(bitOr(bitShl(d, 24), bitShl(c, 16)), bitOr(bitShl(b, 8), a)))
end
function zpu.op_emulate(op)
 v_push(zpu.rIP + 1)
 zpu.rIP = bitShl(op, 5)
 return "EMULATE " .. op .. "/" .. bitOr(op, 0x20)
end

local function ip_adv()
 zpu.rIP = bitAnd(zpu.rIP + 1, 0xFFFFFFFF)
end

function zpu.run()
 -- NOTE: The ZPU probably can't be trusted to have a consistent memory
 --        access pattern, *unless* it is accessing memory in the IO range.
 --       In the case of the IO range, it's specifically
 --        assumed MMIO will happen there, so the processor bypasses caches.
 --       For now, we're just using the behavior that would be used for 
 --        a naive processor, which is exactly what this file emulates.
 local m = zpu.get32(bitAnd(zpu.rIP, 0xFFFFFFFC))
 local op = split32(m)[bitAnd(zpu.rIP, 3) + 1]
 local lim = zpu.fLastIM
 zpu.fLastIM = false

 -- Bitfield Ops
 if bitAnd(op, 0x80) == 0x80 then ip_adv() op_im(bitAnd(op, 0x7F), lim) zpu.fLastIM = true return "IM " .. bitAnd(op, 0x7F) end -- IM x
 if bitAnd(op, 0xE0) == 0x40 then op_storesp(bitAnd(op, 0x1F)) ip_adv() return "STORESP " .. (bitXor(0x10, bitAnd(op, 0x1F)) * 4) end -- STORESP x
 if bitAnd(op, 0xE0) == 0x60 then op_loadsp(bitAnd(op, 0x1F)) ip_adv() return "LOADSP " .. (bitXor(0x10, bitAnd(op, 0x1F)) * 4) end -- LOADSP x
 if bitAnd(op, 0xF0) == 0x10 then op_addsp(bitAnd(op, 0xF)) ip_adv() return "ADDSP " .. bitAnd(op, 0xF) end -- ADDSP x
 if bitAnd(op, 0xE0) == 0x20 then return zpu.op_emulate(bitAnd(op, 0x1F)) end -- EMULATE x

 if op == 0x04 then zpu.rIP = v_pop() return "POPPC" end -- POPPC
 if op == 0x08 then op_load() ip_adv() return "LOAD" end -- LOAD
 if op == 0x0C then op_store() ip_adv() return "STORE" end -- STORE
 if op == 0x02 then v_push(zpu.rSP) ip_adv() return "PUSHSP" end -- PUSHSP
 if op == 0x0D then zpu.rSP = bitAnd(v_pop(), 0xFFFFFFFC) ip_adv() return "POPSP" end -- POPSP
 if op == 0x05 then op_add() ip_adv() return "ADD" end -- ADD
 if op == 0x06 then op_and() ip_adv() return "AND" end -- AND
 if op == 0x07 then op_or() ip_adv() return "OR" end -- OR
 if op == 0x09 then op_not() ip_adv() return "NOT" end -- NOT
 if op == 0x0A then op_flip() ip_adv() return "FLIP" end -- FLIP
 if op == 0x0B then ip_adv() return "NOP" end -- NOP
 return nil
end

function zpu.run_trace(f, tracestack)
 f:write(zpu.rIP .. " (" .. string.format("%x", zpu.rSP))
 f:flush()
 local cSP = zpu.rSP
 for i = 1, tracestack do
  f:write(string.format("/%x", zpu.get32(cSP)))
  cSP = cSP + 4
 end
 f:write(") :")
 io.flush()
 local op = zpu.run()
 if op == nil then
  f:write("UNKNOWN\n")
 else
  f:write(op .. "\n")
 end
 return op
end
return zpu
