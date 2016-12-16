local bit32, addressbus = computech.bit32, computech.addressbus
local tilebox = {
	type = "fixed",
	fixed = {{-0.5, -0.5, -0.5, 0.5, -0.3, 0.5}},
}

local function ci(pos)
	return pos.x .. ":" .. pos.y .. ":" .. pos.z
end

local function register_ram(kb)
	local bytes = kb * 1024
	local cache = {}
	local wcache = {}
	local function read_ram(pos, addr)
		if addr >= bytes then
			return 0xFF
		end
		local cin = ci(pos)
		if not cache[cin] then
			cache[cin] = minetest.get_meta(pos):get_string("m")
			if not cache[cin] then
				cache[cin] = string.rep(string.char(0), bytes)
			end
		end
		return cache[cin]:byte(addr + 1)
	end
	local function write_ram(pos, addr, value)
		if addr >= bytes then
			return
		end
		local cin = ci(pos)
		-- this call also initializes cache
		if read_ram(pos, addr) == value then
			return
		end
		local d = cache[cin]
		local s, e = d:sub(1, addr), d:sub(addr + 2)
		cache[cin] = table.concat({s, string.char(value), e})
		wcache[cin] = true
	end
	local function flush_ram(pos)
		local cin = ci(pos)
		if cache[cin] and wcache[cin] then
			minetest.get_meta(pos):set_string("m", cache[cin])
			-- cache continues to exist.
			wcache[cin] = nil
		end
	end
	local function reset_ram(pos)
		-- reset cache
		local cin = ci(pos)
		cache[cin] = nil
		wcache[cin] = nil
		local nw = string.rep(string.char(0), bytes)
		minetest.get_meta(pos):set_string("m", nw)
	end
	minetest.register_node("computech_addressbus:ram" .. kb, {
		description = "Computech RAM (" .. kb .. "KiB)",
		tiles = {"computech_addressbus_ram_top.png", "computech_addressbus_ram_top.png",
			"computech_addressbus_port.png", "computech_addressbus_port.png",
			"computech_addressbus_port.png", "computech_addressbus_port.png"},
		paramtype = "light",
		drawtype = "nodebox",
		node_box = tilebox,
		groups = {dig_immediate = 2},
		on_construct = function (pos)
			reset_ram(pos)
		end,
		computech_addressbus = {
			-- Note: This routine won't work for a 4GB RAM.
			-- However, such a thing shouldn't ever exist.
			read32 = function (pos, msg, dir)
				local addr = assert(msg.params[1])
				if addr < bytes then
					local a = read_ram(pos, addr) or 0xFF
					local b = read_ram(pos, addr + 1) or 0xFF
					local c = read_ram(pos, addr + 2) or 0xFF
					local d = read_ram(pos, addr + 3) or 0xFF
					msg.respond((a * 0x1000000) + (b * 0x10000) + (c * 0x100) + d)
				end
			end,
			write32 = function (pos, msg, dir)
				local addr = assert(msg.params[1])
				if addr < bytes then
					local val = assert(msg.params[2])
					local a = bit32.band(val, 0xFF000000) / 0x1000000
					local b = bit32.band(val, 0xFF0000) / 0x10000
					local c = bit32.band(val, 0xFF00) / 0x100
					local d = bit32.band(val, 0xFF)
					write_ram(pos, addr, a)
					write_ram(pos, addr + 1, b)
					write_ram(pos, addr + 2, c)
					write_ram(pos, addr + 3, d)
					msg.respond()
				end
			end,
			extent = function (pos, msg, dir)
				msg.respond(bytes)
			end,
			flush = function (pos, msg, dir)
				flush_ram(pos)
			end
		}
	})
end
register_ram(64)

local inspector_roms = nil
local function update_inspector(pos, message)
	local meta = minetest.get_meta(pos)

	local v = tonumber(meta:get_string("value")) or 0
	meta:set_string("value", tostring(v))
	if not inspector_roms then
		local items = "Select item to flash"
		for k, v in pairs(addressbus.roms) do
			items = items .. "," .. minetest.formspec_escape(k)
		end
		inspector_roms = items
	end
	local confirmation = ""
	if message then
		confirmation = "label[6,1;" .. minetest.formspec_escape(message) .. "]"
	end
	meta:set_string("formspec", "size[10,8]" ..
		"button[1,1;1,1;am;<]"..
		"label[2,1;" .. string.format("0x%08x", bit32.band(0xFFFFFFFF, meta:get_int("address"))) .. "]"..
		"button[4,1;1,1;ap;>]"..
		"button[5,1;1,1;ar;R]"..
		"button[5,2;1,1;aw;W]"..
		"label[2,2;" .. string.format("0x%08x", v) .. "]"..
		"button[1,2;1,1;vm;-]"..
		"button[4,2;1,1;vp;+]"..
		"button[6,2;1,1;ex;Ex]"..
		"dropdown[1,3;4,1;flash;" .. inspector_roms .. ";ROM Flash]"..
		confirmation..
		"button_exit[9,1;1,0;exit;X]")
end
minetest.register_node("computech_addressbus:inspector", {
	description = "Computech Addressbus Inspector",
	tiles = {"computech_addressbus_inspector_top.png", "computech_addressbus_inspector_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2},
	on_construct = function (pos)
		update_inspector(pos)
	end,
	on_receive_fields = function (pos, _, fields, sender)
		local message = nil
		local meta = minetest.get_meta(pos)
		if fields["am"] then
			meta:set_int("address", bit32.band(0xFFFFFFFF, meta:get_int("address") - 1))
		end
		if fields["ap"] then
			meta:set_int("address", bit32.band(0xFFFFFFFF, meta:get_int("address") + 1))
		end
		-- I put this as a string to avoid signed clipping, forgot about it for address,
		-- and everything worked out anyway. Well, it's set now.
		local v = bit32.band(0xFFFFFFFF, tonumber(meta:get_string("value")) or 0)
		if fields["vm"] then
			v = bit32.band(0xFFFFFFFF, v - 1)
			meta:set_string("value", tostring(v))
		end
		if fields["vp"] then
			v = bit32.band(0xFFFFFFFF, v + 1)
			meta:set_string("value", tostring(v))
		end
		local a = bit32.band(0xFFFFFFFF, meta:get_int("address"))
		if fields["ar"] then
			local v = 0xFFFFFFFF
			addressbus.send_all(pos, addressbus.wrap_message("read32", {a}, function (r) v = bit32.band(v, r) end))
			meta:set_string("value", tostring(v))
		end
		if fields["aw"] then
			addressbus.send_all(pos, addressbus.wrap_message("write32", {a, v}, function() end))
		end
		if fields["flash"] then
			local flashitem = fields["flash"]
			local rom = addressbus.roms[flashitem]
			if rom then
				local romulen = math.ceil(rom:len() / 4)
				for i = 0, romulen - 1 do
					local a, b, c, d = rom:byte(1), rom:byte(2), rom:byte(3), rom:byte(4)
					a = a or 0
					b = b or 0
					c = c or 0
					d = d or 0
					local addr = i * 4
					local v = d + (c * 0x100) + (b * 0x10000) + (a * 0x1000000)
					addressbus.send_all(pos, addressbus.wrap_message("write32", {addr, v}, function() end))
					rom = rom:sub(5)
				end
				message = "flash OK"
			else
				message = "invalid ROM"
			end
		end
		if fields["ex"] then
			local ext = 0
			addressbus.send_all(pos, addressbus.wrap_message("extent", {}, function(a)
				if a > ext then
					ext = a
				end
			end))
			message = "len: " .. ext
		end
		update_inspector(pos, message)
		addressbus.send_all(pos, addressbus.wrap_message("flush", {}, function() end))
	end,
	computech_addressbus = {}
})

-- communications helper!
minetest.register_node("computech_addressbus:1wr", {
	description = "Computech 'A Word Of RAM'",
	tiles = {"computech_addressbus_1wr_top.png", "computech_addressbus_1wr_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2},
	on_construct = function (pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("val", 0)
		meta:set_string("infotext", "Value: 0")
	end,
	computech_addressbus = {
		read32 = function (pos, msg, dir)
			local meta = minetest.get_meta(pos)
			local addr = msg.params[1]
			if addr == 0 then
				msg.respond(bit32.band(meta:get_int("val"), 0xFFFFFFFF))
			end
		end,
		write32 = function (pos, msg, dir)
			local meta = minetest.get_meta(pos)
			if msg.params[1] == 0 then
				meta:set_int("val", msg.params[2])
				meta:set_string("infotext", "Value: " .. msg.params[2])
				msg.respond()
			end
		end,
		extent = function (pos, msg, dir)
			msg.respond(4)
		end,
		flush = function (pos, msg, dir)
		end
	}
})

-- The following caches should be completely wiped when any component flushes:
-- This direction cache is used by all components for directions.
local direction_cache = {}
-- This MCU extent cache is used by MCUs for the sideport extents.
local mcu_extent_cache = {}
local function flush_caches()
	direction_cache = {}
	mcu_extent_cache = {}
end

-- For 3-way components, looking from the sideport:
-- 1 is right, 2 is sideport, 3 is left.
-- For 2-way components, same but without 2.
local function find_direction(pos, dir)
	local cin = ci(pos)
	local dc = direction_cache[cin]
	if not dc then
		local n = minetest.get_node(pos)
		if not n.param2 then return nil end
		dc = n.param2
		direction_cache[cin] = dc
	end
	-- presumably, 0 is "front". This has backwards mapping and a forward AB direction map.
	local mapping = {
		"000010",
		"100000",
		"000001",
		"010000",
	}
	local a, b = bit32.band(dir - dc, 3), mapping[((dir + dc) % 4) + 1]
	return a, b
end

local function mcu_get_extent(pos, sideport)
	-- This gets called on most memory accesses.
	local _, result = nil, nil
	if sideport then
		_, result = find_direction(pos, 2)
	else
		_, result = find_direction(pos, 1)
	end
	local ext = 0
	local msg = addressbus.wrap_message("extent", {}, function (extn)
		if extn > ext then
			ext = extn
		end
	end)
	addressbus.send_all(pos, msg, result)
	return ext
end

local function mcu_forwarder(pos, msg, dir)
	if find_direction(pos, dir) == 3 then
		-- Caching stuff because this is critical code.
		local cin = ci(pos)
		local a = mcu_extent_cache[cin]
		if not a then
			a = mcu_get_extent(pos, true)
			mcu_extent_cache[cin] = a
		end
		local addr, val = (table.unpack or unpack)(msg.params)
		-- Re-package the message, and re-send.
		-- The depth limit should catch nasty cases.
		local portdir = 2
		if addr >= a then
			addr = bit32.band(addr - a, 0xFFFFFFFF)
			portdir = 1
		end
		local newmsg = addressbus.wrap_message(msg.id, {addr, val}, msg.respond)
		local _, port = find_direction(pos, portdir)
		addressbus.send_all(pos, newmsg, port)
	end
end
minetest.register_node("computech_addressbus:mcu", {
	description = "Computech Memory Chain Unit",
	tiles = {"computech_addressbus_mcu_top.png", "computech_addressbus_mcu_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_block.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	paramtype2 = "facedir",
	groups = {dig_immediate = 2},
	computech_addressbus = {
		-- These are basically the same
		read32 = mcu_forwarder,
		write32 = mcu_forwarder,
		extent = function (pos, msg, dir)
			if find_direction(pos, dir) == 3 then
				-- CPU wants to know extent.
				local a = mcu_get_extent(pos, true)
				local b = mcu_get_extent(pos, false)
				msg.respond(a + b)
			end
		end,
		flush = function (pos, msg, dir)
			if find_direction(pos, dir) == 3 then
				-- Flush should be propagated from CPUs outwards to all.
				local _, flushA = find_direction(pos, 1)
				local _, flushB = find_direction(pos, 2)
				addressbus.send_all(pos, msg, flushA)
				addressbus.send_all(pos, msg, flushB)
				-- This flushes ALL caches, it's intentional:
				-- since any cache that doesn't disappear
				-- by the end of that CPU's tick is stale.
				flush_caches()
			end
		end,
		interrupt = function (pos, msg, dir)
			-- If interrupt is CPU-side, ignore.
			-- Otherwise, it must be forwarded (as-is for simplicity)
			if find_direction(pos, dir) ~= 3 then
				local _, cpudir = find_direction(pos, 3)
				addressbus.send_all(pos, msg, cpudir)
			end
		end
	}
})
