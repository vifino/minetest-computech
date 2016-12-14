local zpu_rate = 0.02
local zpu_clock = 25
local mp = minetest.get_modpath("computech_machine_zpu")
local bit32, addressbus = computech.bit32, computech.addressbus

-- REB ROM
local f = io.open(mp .. "/reb.bin", "rb")
addressbus.roms["computech_addressbus:zpu:reb"] = f:read(0x80000)
f:close()

local zpu = loadfile(mp .. "/zpu.lua")
local zpu_emus = loadfile(mp .. "/zpu_emus.lua")
local globalZPU = zpu()
zpu_emus(globalZPU)

local bit32, bettertimers = computech.bit32, computech.bettertimers

local console_lines = 6

local function guizpu(pos)
	local meta = minetest.get_meta(pos)
	local formspec = "size[8," .. ((console_lines / 2) + 1) .. "]"
	for l = 1, console_lines do
		formspec = formspec .. "label[0, " .. ((l - 1) / 2) .. ";" .. minetest.formspec_escape(meta:get_string("c" .. l)) ..  "]"
	end
	local hd = ((console_lines / 2) + 0.5)
	formspec = formspec .. "button[6," .. hd .. ";2,1;submit;Send]"
	                    .. "field[1," .. hd .. ";5,1;stext;;]"
	meta:set_string("formspec", formspec)
end

-- Newlines must be their own strings.
local function console_append(pos, str)
	local meta = minetest.get_meta(pos)
	if str == "\n" then
		for l = 1, console_lines - 1 do
			meta:set_string("c" .. l, meta:get_string("c" .. (l + 1)))
		end
		meta:set_string("c" .. console_lines, "")
	else
		meta:set_string("c" .. console_lines, meta:get_string("c" .. console_lines) .. str)
	end
end

local function rfields_zpu(pos, _, fields, sender)
	local meta = minetest.get_meta(pos)
	if fields["submit"] then
		local t = tostring(fields["stext"])
		console_append(pos, t)
		console_append(pos, "\n")
		meta:set_string("cinbuf", meta:get_string("cinbuf") .. t .. "\n")
	end
	guizpu(pos)
end

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
	meta:set_string("cinbuf", "")
	for l = 1, console_lines do
		meta:set_string("c" .. l, "")
	end
	guizpu(pos)
	local timer = minetest.get_node_timer(pos)
	timer:start(1.0)
end
local function zputick(pos)
	local update_console = false
	local meta = minetest.get_meta(pos)
	globalZPU.rIP = meta:get_int("ip")
	globalZPU.rSP = meta:get_int("sp")
	globalZPU.get32 = function (addr)
		if bit32.band(addr, 3) ~= 0 then return 0xFFFFFFFF end
		if addr == 0x80000024 then
			-- UART(O) - there is always space, which means 0x100 must be set.
			return 0x100
		end
		if addr == 0x80000028 then
			-- UART(I)
			local buf = meta:get_string("cinbuf")
			if buf:len() == 0 then return 0 end
			meta:set_string("cinbuf", buf:sub(2))
			return buf:byte(1) + 0x100
		end
		local data = 0xFFFFFFFF
		addressbus.send_all(pos, addressbus.wrap_message("read32", {addr}, function(nd)
			data = bit32.band(data, nd)
		end))
		return data
	end
	globalZPU.set32 = function (addr, data)
		if bit32.band(addr, 3) ~= 0 then return 0xFFFFFFFF end
		if addr == 0x80000024 then
			-- UART(O)
			console_append(pos, string.char(bit32.band(data, 0xFF)))
			update_console = true
			return
		end
		addressbus.send_all(pos, addressbus.wrap_message("write32", {addr, data}, function() end))
	end
	globalZPU.fLastIM = meta:get_int("im") ~= 0
	for i = 1, zpu_clock do
		local disasm = globalZPU.run()
		if not disasm then
			-- Error occurred, instant reboot.
			-- (To fix things, remove the ZPU first!)
			--print("Zpu Error")
			--reset_zpu(pos)
			minetest.set_node(pos, {name = "air"})
			return
		end
	end
	local imr = 0
	if globalZPU.fLastIM then imr = 1 end
	meta:set_int("ip", globalZPU.rIP)
	meta:set_int("sp", globalZPU.rSP)
	meta:set_int("im", imr)
	addressbus.send_all(pos, addressbus.wrap_message("flush", {}, function() end))
	if update_console then
		guizpu(pos)
	end
end

-- Simple enough.

minetest.register_node("computech_machine_zpu:zpu", {
	groups = {dig_immediate = 2, computech_addressbus_cable = 1},
	tiles = {"computech_machine_zpu.png"},
	description = "ZPU",
	on_construct = reset_zpu,
	on_punch = reset_zpu,
	on_receive_fields = rfields_zpu,
	on_timer = bettertimers.create_on_timer("computech_machine_zpu:zpu", zputick, zpu_rate)
})