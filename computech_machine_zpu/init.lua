local zpu_rate = 0.125
local zpu_clock = 180 -- Note! This is divided by the total amount of operating ZPUs.
if jit then
 -- LuaJIT likely - increase clockspeed
 zpu_clock = 425
end
local mp = minetest.get_modpath("computech_machine_zpu")

local profiler = nil -- {<output file>, <symbol table>}

local bit32, addressbus, bettertimers = computech.bit32, computech.addressbus, computech.bettertimers

local profiler_data = nil

-- REB ROM
local function getROM(file)
	local f = io.open(mp .. "/" .. file .. ".bin", "rb")
	local bin = f:read(0x80000)
	f:close()
	return bin
end
addressbus.roms["computech_machine_zpu:reb"] = getROM("reb")

-- Load ZPU, zpu_emus and set bit library.
local zpu = dofile(mp .. "/zpu.lua")
zpu.set_bit32(bit32)
zpu:apply(dofile(mp .. "/zpu_emus.lua"))

local function reset_zpu(pos)
	local memsz = 0
	addressbus.send_all(pos, addressbus.wrap_message("extent", {}, function(nd)
		if nd > memsz then
			memsz = nd
		end
	end))
	local meta = minetest.get_meta(pos)
	meta:set_int("ip", 0)
	meta:set_int("sp", bit32.band(memsz, 0xFFFFFFFC))
	meta:set_int("im", 0)
	meta:set_int("il", 0)
	local timer = minetest.get_node_timer(pos)
	timer:start(1.0)
end

local function zpu_get32(zpu_inst, addr)
	if bit32.band(addr, 3) ~= 0 then return 0xFFFFFFFF end
	local data = 0xFFFFFFFF
	addressbus.send_all(zpu_inst.pos, addressbus.wrap_message("read32", {addr}, function(nd)
		data = bit32.band(data, nd)
	end))
	return data
end

local function zpu_set32(zpu_inst, addr, data)
	if bit32.band(addr, 3) ~= 0 then return 0xFFFFFFFF end
	addressbus.send_all(zpu_inst.pos, addressbus.wrap_message("write32", {addr, data}, function() end))
end

local globalZPU = zpu.new(zpu_get32, zpu_set32)

local function zputick(pos, operating)
	local meta = minetest.get_meta(pos)
	globalZPU.rIP = bit32.band(meta:get_int("ip"), 0xFFFFFFFF)
	globalZPU.rSP = bit32.band(meta:get_int("sp"), 0xFFFFFFFF)
	globalZPU.pos = pos -- Metadata used internally.
	globalZPU.fLastIM = meta:get_int("im") ~= 0
	if meta:get_int("il") ~= 0 then
		if not globalZPU.fLastIM then
			-- Interrupt.
			-- At this point, we could have been just woken from sleep,
			--  which means if the timeslice continues without the interrupt occurring,
			--  then it may well return to sleep before we have a chance.
			-- So do this now.
			globalZPU:op_emulate(1)
			meta:set_int("il", 0)
		end
	end
	if profiler then
		profiler_data = profiler_data or {}
	end
	local frozen = false
	local left = math.ceil(zpu_clock / operating)
	while left > 0 and (not frozen) do
		if profiler_data then profiler_data[globalZPU.rIP] = (profiler_data[globalZPU.rIP] or 0) + 1 end
		local disasm, ipb = globalZPU:run()
		if not disasm then
			if ipb == 0 then
				globalZPU.rIP = bit32.band(globalZPU.rIP + 1, 0xFFFFFFFF)
				globalZPU.fLastIM = false
				if meta:get_int("il") == 0 then
					minetest.set_node(pos, {name = "computech_machine_zpu:zpu_slp"})
					-- zpu_slp doesn't have "il" flag.
				end
				frozen = true
			else
				minetest.set_node(pos, {name = "computech_machine_zpu:zpu_err"})
				meta:set_string("infotext", string.format("Bad op %02x at IP: %08x", ipb, globalZPU.rIP))
				addressbus.send_all(pos, addressbus.wrap_message("flush", {}, function() end))
				return
			end
		end
		left = left - 1
	end
	local imr = 0
	if globalZPU.fLastIM then imr = 1 end
	meta:set_int("ip", globalZPU.rIP)
	meta:set_int("sp", globalZPU.rSP)
	meta:set_int("im", imr)
	addressbus.send_all(pos, addressbus.wrap_message("flush", {}, function() end))
end

local function start_zpu(pos)
	minetest.set_node(pos, {name = "computech_machine_zpu:zpu"})
end
local function stop_zpu(pos)
	if profiler_data then
		local mapping = {}
		local categories = {}
		local syms = io.open(profiler[2], "r")
		local s = syms:read()
		while s do
			local start = tonumber("0x" .. s:sub(1, 8))
			if start then
				s = s:sub(18)
				local st = s:find("\t")
				s = s:sub(st + 1)
				local size = tonumber("0x" .. s:sub(1, 8))
				local name = s:sub(10)
				for a = 0, size - 1 do
					mapping[start + a] = name
				end
			end
			s = syms:read()
		end
		syms:close()
		for k, v in pairs(profiler_data) do
			if mapping[k] then
				categories[mapping[k]] = (categories[mapping[k]] or 0) + v
			end
		end
		table.sort(categories) -- I have no idea how this works.
		local file = io.open(profiler[1], "w")
		for k, v in pairs(categories) do
			file:write(k .. " : " .. v .. "\n")
		end
		file:close()
		profiler_data = nil
		print("Profiler data was written. Have a happy Winter!")
	end
	minetest.set_node(pos, {name = "computech_machine_zpu:zpu_off"})
end

local function abus_interrupt(pos, slp)
	local meta = minetest.get_meta(pos)
	if slp then
		local rIP = bit32.band(meta:get_int("ip"), 0xFFFFFFFF)
		local rSP = bit32.band(meta:get_int("sp"), 0xFFFFFFFF)
		local fLastIM = meta:get_int("im")
		minetest.set_node(pos, {name = "computech_machine_zpu:zpu"})
		meta:set_int("ip", rIP)
		meta:set_int("sp", rSP)
		meta:set_int("im", fLastIM)
	end
	-- The ZPU is definitely active now, set the interrupt latch.
	meta:set_int("il", 1)
end

-- Simple enough.

minetest.register_node("computech_machine_zpu:zpu", {
	groups = {dig_immediate = 2, computech_addressbus_cable = 1, not_in_creative_inventory = 1},
	tiles = {"computech_base_cpu.png^computech_base_cpu_on.png^computech_base_cpu_ac.png"},
	drop = "computech_machine_zpu:zpu_off",
	description = "ZPU<on",
	on_construct = reset_zpu,
	on_punch = stop_zpu,
	on_timer = bettertimers.create_on_timer("computech_machine_zpu:zpu", zputick, zpu_rate),
	computech_addressbus = {
		interrupt = function (pos, msg, dir)
			abus_interrupt(pos, false)
		end
	}
})
minetest.register_node("computech_machine_zpu:zpu_slp", {
	groups = {dig_immediate = 2, computech_addressbus_cable = 1, not_in_creative_inventory = 1},
	tiles = {"computech_base_cpu.png^computech_base_cpu_on.png"},
	drop = "computech_machine_zpu:zpu_off",
	description = "ZPU<on<slp",
	on_construct = reset_zpu,
	on_punch = stop_zpu,
	computech_addressbus = {
		interrupt = function (pos, msg, dir)
			abus_interrupt(pos, true)
		end
	}
})

minetest.register_node("computech_machine_zpu:zpu_err", {
	groups = {dig_immediate = 2, computech_addressbus_cable = 1, not_in_creative_inventory = 1},
	tiles = {"computech_base_cpu.png^computech_base_cpu_on.png^computech_base_cpu_er.png"},
	drop = "computech_machine_zpu:zpu_off",
	description = "ZPU<error",
	on_punch = stop_zpu,
	-- Notably, these must exist in "off" states,
	--  since state changes don't cause cable cache refreshes.
	-- Thus, cables will believe this is "just" a cable block, and won't waste time calling it.
	computech_addressbus = {}
})

minetest.register_node("computech_machine_zpu:zpu_off", {
	groups = {dig_immediate = 2, computech_addressbus_cable = 1},
	tiles = {"computech_base_cpu.png"},
	description = "ZPU",
	on_punch = start_zpu,
	computech_addressbus = {}
})

