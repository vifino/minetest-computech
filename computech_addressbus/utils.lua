local bit32 = computech.bit32
local function register_ram(kb)
	local bytes = kb * 1024
	local rcache = {}
	local cache = {}
	local function ci(pos, addr)
		return pos.x .. ":" .. pos.y .. ":" .. pos.z .. ":" .. addr
	end
	local function write_ram(pos, addr, value)
		if addr >= bytes then
			return
		end
		local cin = ci(pos, addr)
		if rcache[cin] == value then
			return
		end
		rcache[cin] = value
		cache[cin] = value
	end
	local function read_ram(pos, addr)
		if addr >= bytes then
			return 0xFF
		end
		local cin = ci(pos, addr)
		if not rcache[cin] then
			rcache[cin] = minetest.get_meta(pos):get_int("m" .. addr)
		end
		return rcache[cin]
	end
	local function flush_ram(pos)
		for addr = 0, bytes - 1 do
			local cin = ci(pos, addr)
			if cache[cin] then
				minetest.get_meta(pos):set_int("m" .. addr, cache[cin])
				cache[cin] = nil
			end
		end
	end
	local function reset_ram(pos)
		for i = 0, bytes - 1 do
			write_ram(pos, i, 0)
		end
		flush_ram(pos)
	end
	minetest.register_node("computech_addressbus:ram" .. kb, {
		description = "Computech RAM (" .. kb .. "KiB)",
		tiles = {"computech_addressbus_ram.png"},
		groups = {dig_immediate = 2},
		paramtype = "light",
		on_construct = function (pos)
			reset_ram(pos)
		end,
		computech_addressbus = {
			-- Note: This routine won't work for a 4GB RAM.
			-- However, such a thing shouldn't ever exist.
			read32 = function (pos, msg, dir)
				local addr = msg.params[1]
				if addr < bytes then
					local a = read_ram(pos, addr)
					local b = read_ram(pos, addr + 1)
					local c = read_ram(pos, addr + 2)
					local d = read_ram(pos, addr + 3)
					msg.respond((a * 0x1000000) + (b * 0x10000) + (c * 0x100) + d)
				end
			end,
			write32 = function (pos, msg, dir)
				local addr = msg.params[1]
				if addr < bytes then
					local val = msg.params[2]
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
				if msg.params[1] < bytes then
					msg.respond(bytes - 1)
				end
			end,
			flush = function (pos, msg, dir)
				flush_ram(pos)
			end
		}
	})
end
register_ram(64)

local function update_inspector(pos)
	local meta = minetest.get_meta(pos)

	local v = tonumber(meta:get_string("value")) or 0
	meta:set_string("value", tostring(v))

	meta:set_string("formspec", "size[10,8]" ..
		"button[1,1;1,1;am;<]"..
		"label[2,1;" .. string.format("0x%08x", bit32.band(0xFFFFFFFF, meta:get_int("address"))) .. "]"..
		"button[4,1;1,1;ap;>]"..
		"button[6,1;1,1;ar;R]"..
		"button[7,1;1,1;aw;W]"..
		"label[2,2;" .. string.format("0x%08x", v) .. "]"..
		"button[1,3;1,1;vm;-]"..
		"button[2,3;1,1;vp;+]"..
		"button_exit[9,1;1,0;exit;X]")
end
minetest.register_node("computech_addressbus:inspector", {
	description = "Computech Addressbus Inspector",
	tiles = {"computech_addressbus_inspector.png"},
	groups = {dig_immediate = 2},
	paramtype = "light",
	on_construct = function (pos)
		update_inspector(pos)
	end,
	on_receive_fields = function (pos, _, fields, sender)
		local meta = minetest.get_meta(pos)
		if fields["am"] then
			meta:set_int("address", bit32.band(0xFFFFFFFF, meta:get_int("address") - 1))
		end
		if fields["ap"] then
			meta:set_int("address", bit32.band(0xFFFFFFFF, meta:get_int("address") + 1))
		end
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
			computech.addressbus.send_all(pos, computech.addressbus.wrap_message("read32", {a}, function (r) v = bit32.band(v, r) end))
			meta:set_string("value", tostring(v))
		end
		if fields["aw"] then
			computech.addressbus.send_all(pos, computech.addressbus.wrap_message("write32", {a, v}, function() end))
		end
		update_inspector(pos)
	end,
	computech_addressbus = {}
})
