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
		-- note the order - read_ram is poked to ensure cache exists by flush
		if not cache[cin] then
			cache[cin] = minetest.get_meta(pos):get_string("m")
			if not cache[cin] then
				cache[cin] = string.rep(string.char(0), bytes)
			end
		end
		if wcache[cin] then
			local r = wcache[cin][addr]
			if r then return r:byte() end
		end
		return cache[cin]:byte(addr + 1)
	end
	local function write_ram(pos, addr, value)
		local cin = ci(pos)
		if addr >= bytes then
			return
		end
		if not wcache[cin] then wcache[cin] = {} end
		wcache[cin][addr] = string.char(value)
	end
	local function flush_ram(pos)
		local cin = ci(pos)
		if wcache[cin] then
			read_ram(pos, 0) -- poke to ensure cache exists
			local wc = wcache[cin]
			local cc = cache[cin]
			local fc = {}
			local lastcachepoint = nil
			for i = 0, bytes - 1 do
				if wc[i] then
					if lastcachepoint then
						-- i is actually (i + 1) - 1
						-- (convert to string coordinates,
						--  -1 because we don't want to include current char)
						table.insert(fc, cache[cin]:sub(lastcachepoint + 1, i))
						lastcachepoint = nil
					end
					table.insert(fc, wc[i])
				else
					if not lastcachepoint then
						lastcachepoint = i
					end
				end
			end
			if lastcachepoint then
				table.insert(fc, cache[cin]:sub(lastcachepoint + 1))
			end
			cache[cin] = table.concat(fc)
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
				-- Note that the ROM should never exceed 0x7FFFFFFF bytes or so,
				-- and thus there isn't half the safety checks on this that I'd usually use
				local romulen = math.ceil(rom:len() / 256)
				local r = 0
				for i = 0, romulen - 1 do
					local lj = i
					minetest.after(lj * (2 / 256), function ()
						local addr = lj * 256
						-- 64 * 4 = 256
						for s = 0, 63 do
							local a, b, c, d = rom:byte(addr + 1), rom:byte(addr + 2), rom:byte(addr + 3), rom:byte(addr + 4)
							a = a or 0
							b = b or 0
							c = c or 0
							d = d or 0
							local v = d + (c * 0x100) + (b * 0x10000) + (a * 0x1000000)
							addressbus.send_all(pos, addressbus.wrap_message("write32", {addr, v}, function() end))
							addr = addr + 4
						end
						r = r + 1
						if r == romulen then
							addressbus.send_all(pos, addressbus.wrap_message("flush", {}, function() end))
							update_inspector(pos, "flash OK")
						else
							update_inspector(pos, "flash " .. math.floor((r / romulen) * 100) .. "%")
						end
					end)
				end
				message = "flash begun"
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
	computech_addressbus = {
		interrupt = function (pos, msg, dir)
			update_inspector(pos, "interrupt")
		end
	}
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
	if dir > 3 then return nil, nil end
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
		-- Notably, doing things this way ensures that
		local portdir = 2
		if addr >= a then
			addr = bit32.band(addr - a, 0xFFFFFFFF)
			portdir = 1
		end
		local newmsg = addressbus.wrap_message(msg.id, {addr, val}, msg.respond)
		local _, port = find_direction(pos, portdir)
		addressbus.send_all(pos, newmsg, port)
	else
		-- Messages CAN be forwarded backwards if they're in the 0x80000000 range.
		-- This allows IO devices to perform DMA,
		--  since the IO divider would swap things around.
		if msg.params[1] >= 0x80000000 then
			local _, port = find_direction(pos, 3)
			-- Forward the original message to the CPU bus.
			addressbus.send_all(pos, msg, port)
		end
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
			-- Send it everywhere.
			addressbus.send_all(pos, msg)
			-- This flushes ALL caches, it's intentional:
			-- since any cache that doesn't disappear
			-- by the end of that CPU's tick is stale.
			flush_caches()
		end,
		interrupt = function (pos, msg, dir)
			-- If interrupt is CPU-side, ignore.
			-- Otherwise, it must be forwarded, and if it's from the next peripheral, the PID must be incremented.
			local nd = find_direction(pos, dir)
			if nd ~= 3 then
				local newmsg = msg
				if nd == 1 then
					newmsg = addressbus.wrap_message(msg.id, {msg.params[1] + 1}, msg.respond)
				end
				local _, cpudir = find_direction(pos, 3)
				addressbus.send_all(pos, newmsg, cpudir)
			end
		end
	}
})

local function bridge_forwarder(pos, msg, dir)
	local mapping = {
		"110001",
		"010011",
		"110010",
		"100011",
	}
	local addr, val = (table.unpack or unpack)(msg.params)
	addr = bit32.bxor(addr, 0x80000000)
	local newmsg = addressbus.wrap_message(msg.id, {addr, val}, msg.respond)
	local m = mapping[dir + 1]
	if m then
		addressbus.send_all(pos, newmsg, m)
	end
end
minetest.register_node("computech_addressbus:iobridge", {
	description = "Computech IO Bridge Unit",
	tiles = {"computech_addressbus_iobridge_top.png", "computech_addressbus_iobridge_top.png",
		"computech_addressbus_port.png", "computech_addressbus_port.png",
		"computech_addressbus_block.png", "computech_addressbus_port.png"},
	paramtype = "light",
	drawtype = "nodebox",
	node_box = tilebox,
	groups = {dig_immediate = 2},
	computech_addressbus = {
		-- These are basically the same
		read32 = bridge_forwarder,
		write32 = bridge_forwarder,
		extent = function (pos, msg, dir)
		end,
		flush = function (pos, msg, dir)
			addressbus.send_all(pos, msg)
		end,
		interrupt = function (pos, msg, dir)
			addressbus.send_all(pos, msg)
		end
	}
})
