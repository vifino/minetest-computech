local bit32, addressbus = computech.bit32, computech.addressbus
local tilebox = {
	type = "fixed",
	fixed = {{-0.5, -0.5, -0.5, 0.5, -0.3, 0.5}},
}

local function dma_rw(pos, address)
	local nv = 0xFFFFFFFF
	local newmsg = addressbus.wrap_message("read32", {address}, function (val)
		nv = bit32.band(nv, val)
	end)
	addressbus.send_all(pos, newmsg)
	return nv
end
local function dma_ww(pos, address, word)
	local newmsg = addressbus.wrap_message("write32", {address, word}, function () end)
	addressbus.send_all(pos, newmsg)
end
local function dma_rb(pos, address)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	local w = dma_rw(pos, target)
	return bit32.band(0xFF000000, bit32.lshift(w, remain * 8)) / 0x1000000
end
local function dma_wb(pos, address, byte)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	local w = dma_rw(pos, target)
	local mask = 0xFF000000
	local mask2 = 0xFFFFFFFF
	local ormask = bit32.lshift(byte, 24 - (remain * 8))
	mask = bit32.rshift(mask, remain * 8)
	mask2 = bit32.bxor(0xFFFFFFFF, mask)
	dma_ww(pos, address, bit32.bor(ormask, bit32.band(w, mask2)))
end

local function dma_read(pos, address, len)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	local data = ""
	if remain ~= 0 then
		for i = remain, 3 do
			if len > 0 then
				data = data .. dma_rb(pos, target + i)
				len = len - 1
			else
				return data
			end
		end
		target = bit.band(target + 4, 0xFFFFFFFF)
	end
	for i = 1, math.ceil(len / 4) do
		local w = dma_rw(pos, target)
		data = data .. table.concat({
			string.char(bit.band(w, 0xFF000000) / 0x1000000),
			string.char(bit.band(w, 0xFF0000) / 0x10000),
			string.char(bit.band(w, 0xFF00) / 0x100),
			string.char(bit.band(w, 0xFF))
        })
		target = bit.band(target + 4, 0xFFFFFFFF)
	end
	return data:sub(1, len)
end
local function dma_write(pos, address, data)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	if remain ~= 0 then
		for i = remain, 3 do
			if data:len() > 0 then
				dma_wb(pos, target + i, data:byte(1))
				data = data:sub(2)
			else
				return
			end
		end
		target = bit.band(target + 4, 0xFFFFFFFF)
	end
	local mclen = math.floor(len / 4)
	for i = 1, mclen do
		local o = (i - 1) * 4
		local a, b, c, d = data:byte(o + 1), data:byte(o + 2), data:byte(o + 3), data:byte(o + 4)
		local r = (a * 0x1000000) + (b * 0x10000) + (c * 0x100) + d
		dma_ww(pos, target + o, r)
	end
	data = data:sub((mclen * 4) + 1)
	target = target + (mclen * 4)
	for i = 1, data:len() do
		dma_wb(pos, target + i, data:byte(i))
	end
end

-- Digiline I/O Chip Specification
-- 0x00-0x03: S/ID Shorts: 0x0010, 0x0001 (0x00100001)
-- 0x04-0x07: Channel Buffer Loc.
-- 0x08-0x0B: Data Buffer Loc.
-- 0x0C: Channel Buffer Size.
-- 0x0D: Data Buffer Size.
-- 0x0E: Command Byte. Always reads 0, writing can cause things.
--       Command 0: NOP.
--       Command 1: Send a message over the Digiline bus.
--       Command 2: Read a message on the Digiline bus.
--       Command 3: Confirm interrupt enable.
-- 0x0F: Available messages counter.
-- If interrupts are enabled,
--  this device will fire an interrupt when a message is received,
--  unless there is a message waiting.
local function dio_send_buffers(pos)
	local meta = minetest.get_meta(pos)
	local buffer_count = meta:get_int("s_count")
	for i = 1, buffer_count do
		local c, d = meta:get_string("sc" .. i), meta:get_string("sd" .. i)
		meta:set_string("sc" .. i, "")
		meta:set_string("sd" .. i, "")
		digiline:receptor_send(pos, digiline.rules.default, c, m)
	end
	meta:set_int("s_count", 0)
	return false -- stop timer
end

local dio_handlers = {}
dio_handlers[0] = function (pos, data)
	local meta = minetest.get_meta(pos)
	if not data then
		return 0x00100001
	end
end
dio_handlers[4] = function (pos, data)
	local meta = minetest.get_meta(pos)
	if data then
		meta:set_int("cba", data)
	else
		return bit32.band(meta:get_int("cba"), 0xFFFFFFFF)
	end
end
dio_handlers[8] = function (pos, data)
	local meta = minetest.get_meta(pos)
	if data then
		meta:set_int("dba", data)
	else
		return bit32.band(meta:get_int("dba"), 0xFFFFFFFF)
	end
end
dio_handlers[12] = function (pos, data)
	local meta = minetest.get_meta(pos)
	if data then
		meta:set_int("wr", data)
		-- They have access to *system RAM* and yet can't talk to each other.
		-- That's the way things go these days.
		local ac = bit32.bxor(0x80000000, bit32.band(meta:get_int("cba"), 0xFFFFFFFF))
		local ad = bit32.bxor(0x80000000, bit32.band(meta:get_int("dba"), 0xFFFFFFFF))
		local lc = bit32.band(data, 0xFF000000) / 0x1000000
		local ld = bit32.band(data, 0xFF0000) / 0x10000
		local cmd = bit32.band(data, 0xFF00) / 0x100
		if cmd == 1 then
			-- Write
			local buffer_count = meta:get_int("s_count") + 1
			local c, d = dma_read(pos, ac, lc), dma_read(pos, ad, ld)
			meta:set_string("sc" .. buffer_count, c)
			meta:set_string("sd" .. buffer_count, d)
			meta:set_int("s_count", buffer_count)
			-- The node timer is more or less a fallback in case the server restarts.
			local nt = minetest.get_node_timer(pos)
			if not nt:is_started() then
				nt:start(1.0)
			end
			minetest.after(0.05, function ()
				dio_send_buffers(pos)
			end)
		end
		if cmd == 2 then
			-- Read
			local buffer_count = meta:get_int("r_count", data) - 1
			local c, d = meta:get_string("rc1"), meta:get_string("rd1")
			
			for i = 1, buffer_count do
				meta:set_string("rc" .. i, meta:get_string("rc" .. (i + 1)))
				meta:set_string("rd" .. i, meta:get_string("rd" .. (i + 1)))
			end
			meta:set_string("rc" .. (buffer_count + 1), "")
			meta:set_string("rd" .. (buffer_count + 1), "")
			meta:set_int("r_count", buffer_count)
			dma_write(pos, ac, d:sub(1, lc))
			dma_write(pos, ad, d:sub(1, ld))
		end
		if cmd == 3 then
			-- Enable interrupts
		end
	else
		return bit32.band(meta:get_int("dba"), 0xFFFF0000) + math.min(meta:get_int("r_count"), 255)
	end
end
local function dio_reset(pos)
	local meta = minetest.get_meta(pos)
	meta:set_int("r_count", 0)
	meta:set_int("s_count", 0)
	meta:set_int("cba", 0)
	meta:set_int("dba", 0)
	meta:set_int("wr", 0)
end
local function dio_digiline(pos, node, channel, msg)
	if channel then
		local buffer_count = meta:get_int("r_count") + 1
		meta:set_string("rc" .. buffer_count, tostring(channel))
		meta:set_string("rd" .. buffer_count, tostring(msg))
		meta:set_int("r_count", buffer_count)
	end
end
local function dio_handler(pos, msg, dir)
	local addr, data = math.floor(msg.params[1] / 4), msg.params[2]
	if dio_handlers[addr] then
		msg.respond(dio_handlers[addr](pos, data))
	end
end
minetest.register_node("computech_addressbus:digiline_io", {
	description = "Computech Digiline IO Chip <UNTESTED>",
	tiles = {"computech_addressbus_dio_top.png", "computech_addressbus_dio_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2, computech_addressbus_cable = 1},
	on_construct = dio_reset,
	on_timer = dio_send_buffers,
	digiline = {
		receptor = {},
		effector = {
			action = dio_digiline
		},
	},
	computech_addressbus = {
		read32 = dio_handler,
		write32 = dio_handler,
		extent = function (pos, msg, dir)
			msg.respond(0x10)
		end,
		flush = function (pos, msg, dir)
			dio_send_buffers(pos)
		end
	}
})
