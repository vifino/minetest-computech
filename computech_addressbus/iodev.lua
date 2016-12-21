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
local function dma_fl(pos)
	local newmsg = addressbus.wrap_message("flush", {}, function () end)
	addressbus.send_all(pos, newmsg)
end

local function dma_rb(pos, address)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	local w = dma_rw(pos, target)
	-- remain val->shift: 24, 16, 8, 0
	local shift = 24 - (remain * 8)
	--print("DMA_Rbw " .. string.format("address %x s%i", target, shift))
	w = bit32.rshift(w, shift)
	return bit32.band(0xFF, w)
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
	--print(string.format("DMA_WB%x %x %x > %x", mask, mask2, ormask, address))
	dma_ww(pos, target, bit32.bor(ormask, bit32.band(w, mask2)))
end

local function dma_read(pos, address, len)
	local target = bit32.band(address, 0xFFFFFFFC)
	local remain = address - target
	local data = ""
	if remain ~= 0 then
		for i = remain, 3 do
			if data:len() < len then
				data = data .. string.char(dma_rb(pos, target + i))
			else
				return data
			end
		end
		target = bit32.band(target + 4, 0xFFFFFFFF)
	end
	for i = 1, math.ceil(len / 4) do
		local w = dma_rw(pos, target)
		data = data .. table.concat({
			string.char(bit32.band(math.floor(w / 0x1000000), 0xFF)),
			string.char(bit32.band(math.floor(w / 0x10000), 0xFF)),
			string.char(bit32.band(math.floor(w / 0x100), 0xFF)),
			string.char(bit32.band(w, 0xFF))
        	})
		target = bit32.band(target + 4, 0xFFFFFFFF)
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
		target = bit32.band(target + 4, 0xFFFFFFFF)
	end
	local mclen = math.floor(data:len() / 4)
	for i = 1, mclen do
		local o = (i - 1) * 4
		local a, b, c, d = data:byte(o + 1), data:byte(o + 2), data:byte(o + 3), data:byte(o + 4)
		local r = (a * 0x1000000) + (b * 0x10000) + (c * 0x100) + d
		dma_ww(pos, bit32.band(target + o, 0xFFFFFFFF), math.floor(r))
	end
	data = data:sub((mclen * 4) + 1)
	target = target + (mclen * 4)
	for i = 1, data:len() do
		dma_wb(pos, bit32.band(target + (i - 1), 0xFFFFFFFF), data:byte(i))
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
-- 0x0F: Available messages counter.
-- This device will fire an interrupt when a message is received,
--  unless there is a message waiting.
local function dio_send_buffers(pos)
	local n = minetest.get_node(pos)
	if not n then return false end
	if n.name ~= "computech_addressbus:digiline_io" then
		return false
	end
	local meta = minetest.get_meta(pos)
	local buffer_count = meta:get_int("s_count")
	for i = 1, buffer_count do
		local c, d = meta:get_string("sc" .. i), meta:get_string("sd" .. i)
		meta:set_string("sc" .. i, "")
		meta:set_string("sd" .. i, "")
		digiline:receptor_send(pos, digiline.rules.default, c, d)
	end
	meta:set_int("s_count", 0)
	return false -- stop timer
end
local function dio_wm(meta, bc)
	if bc == 0 then
		meta:set_string("infotext", "No messages.")
		return
	end
	if bc == 1 then
		meta:set_string("infotext", "Message available.")
		return
	end
	meta:set_string("infotext", bc .. " waiting messages.")
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
		-- They have access to *system RAM* and yet can't talk to each other.
		-- That's the way things go these days.
		local ac = bit32.bxor(0x80000000, meta:get_int("cba"))
		local ad = bit32.bxor(0x80000000, meta:get_int("dba"))
		local lc = math.floor(bit32.band(data, 0xFF000000) / 0x1000000)
		local ld = math.floor(bit32.band(data, 0xFF0000) / 0x10000)
		local cmd = math.floor(bit32.band(data, 0xFF00) / 0x100)
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
			local c, d = meta:get_string("rc1"):sub(1, lc), meta:get_string("rd1"):sub(1, ld)
			if buffer_count == -1 then
				buffer_count = 0
				c = ""
				d = ""
			end
			
			for i = 1, buffer_count do
				meta:set_string("rc" .. i, meta:get_string("rc" .. (i + 1)))
				meta:set_string("rd" .. i, meta:get_string("rd" .. (i + 1)))
			end
			meta:set_string("rc" .. (buffer_count + 1), "")
			meta:set_string("rd" .. (buffer_count + 1), "")
			meta:set_int("r_count", buffer_count)
			data = (c:len() * 0x1000000) + (d:len() * 0x10000)
			dma_write(pos, ac, c)
			dma_write(pos, ad, d)
			dio_wm(meta, buffer_count)
			dma_fl(pos)
		end
		meta:set_int("wr", data)
	else
		return bit32.band(meta:get_int("wr"), 0xFFFF0000) + math.min(meta:get_int("r_count"), 255)
	end
end
local function dio_reset(pos)
	local meta = minetest.get_meta(pos)
	meta:set_int("r_count", 0)
	meta:set_int("s_count", 0)
	meta:set_int("cba", 0)
	meta:set_int("dba", 0)
	meta:set_int("wr", 0)
	dio_wm(meta, 0)
end
local function dio_digiline(pos, node, channel, msg)
	if channel then
		local meta = minetest.get_meta(pos)
		local buffer_count = meta:get_int("r_count") + 1
		meta:set_string("rc" .. buffer_count, tostring(channel):sub(1, 255))
		meta:set_string("rd" .. buffer_count, tostring(msg):sub(1, 255))
		meta:set_int("r_count", buffer_count)
		dio_wm(meta, buffer_count)
		-- If nothing's currently waiting, cause an interrupt.
		if buffer_count == 1 then
			local newmsg = addressbus.wrap_message("interrupt", {0}, function () end)
			addressbus.send_all(pos, newmsg)
		end
	end
end
local function dio_handler(pos, msg, dir)
	local addr, data = msg.params[1], msg.params[2]
	if msg.id == "read32" then
		data = nil
		--print("DIO Rd." .. addr .. ",")
		--else
		--print("DIO Wr." .. addr .. "," .. data)
	end
	if dio_handlers[addr] then
		msg.respond(dio_handlers[addr](pos, data))
	end
end
minetest.register_node("computech_addressbus:digiline_io", {
	description = "Computech Digiline IO Chip",
	tiles = {"computech_addressbus_dio_top.png", "computech_addressbus_dio_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2},
	on_construct = dio_reset,
	on_punch = dio_reset,
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
