if not computech then
	error("computech_base is required.")
end

local mp = minetest.get_modpath("computech_addressbus")

local addressbus = {}
computech.addressbus = addressbus

-- Wrap a message for transmission.
function addressbus.wrap_message(id, param, rsp)
	local m = {}
	m.places = {}
	m.id = id
	m.params = param
	m.respond = rsp
	return m
end

-- Send a wrapped message.
function addressbus.send(pos, msg, dir)
	pos = vector.add(pos, dir)
	local str = pos.x .. ":" .. pos.y .. ":" .. pos.z
	if msg.places[str] then
		return
	else
		msg.places[str] = true
	end
	local node = minetest.get_node(pos)
	local nodedef = minetest.registered_nodes[node.name]
	if nodedef then
		if nodedef.groups.computech_addressbus_cable then
			local specialprefix = "computech_addressbus:cable_"
			local dirs = nil
			if node.name:sub(1, specialprefix:len()) == specialprefix then
				dirs = node.name:sub(specialprefix:len() + 1)
			end
			addressbus.send_all(pos, msg, dirs)
		end
		if nodedef.computech_addressbus then
			if nodedef.computech_addressbus[msg.id] then
				nodedef.computech_addressbus[msg.id](pos, msg, minetest.dir_to_facedir(vector.multiply(dir, -1), true))
				return true
			end
		end
	end
	return false
end
function addressbus.send_all(pos, msg, str)
	if str == nil then str = "111111" end
	local dirs={
		{x = 1, y = 0, z = 0},
		{x = -1, y = 0, z = 0},
		{x = 0, y = 1, z = 0},
		{x = 0, y = -1, z = 0},
		{x = 0, y = 0, z = 1},
		{x = 0, y = 0, z = -1}
	}
	for i = 1, 6 do
		if str:sub(i, i) == "1" then
			addressbus.send(pos, msg, dirs[i])
		end
	end
end
local function getCableId(xp, xm, yp, ym, zp, zm)
	local str = xp
	str = str .. xm
	str = str .. yp
	str = str .. ym
	str = str .. zp
	str = str .. zm
	return str
end

local isCable = {}
local cableIdMap = {}

local function recalcSide(res, ind, p)
	local n = minetest.get_node(p)
	if n == nil then return res end
	local nodedef = minetest.registered_nodes[n.name]
	if not nodedef.groups.computech_addressbus_cable then
		if not nodedef.computech_addressbus then
			return res
		end
	end
	return res:sub(1, ind) .. "1" .. res:sub(ind + 2)
end
local function recalcCable(p)
	local n = minetest.get_node(p)
	if n == nil then return end
	if not isCable[n.name] then return end
	local result = "000000"
	result = recalcSide(result, 0, vector.add(p, vector.new(1, 0, 0)))
	result = recalcSide(result, 1, vector.add(p, vector.new(-1, 0, 0)))
	result = recalcSide(result, 2, vector.add(p, vector.new(0, 1, 0)))
	result = recalcSide(result, 3, vector.add(p, vector.new(0, -1, 0)))
	result = recalcSide(result, 4, vector.add(p, vector.new(0, 0, 1)))
	result = recalcSide(result, 5, vector.add(p, vector.new(0, 0, -1)))
	minetest.set_node(p, {name = cableIdMap[result]})
end
local function recalcAdjCable(pos)
	recalcCable(vector.add(pos, vector.new(0,1,0)))
	recalcCable(vector.add(pos, vector.new(0,-1,0)))
	recalcCable(vector.add(pos, vector.new(1,0,0)))
	recalcCable(vector.add(pos, vector.new(-1,0,0)))
	recalcCable(vector.add(pos, vector.new(0,0,1)))
	recalcCable(vector.add(pos, vector.new(0,0,-1)))
end
-- recalculation callbacks
minetest.register_on_placenode(function(pos)
	recalcAdjCable(pos)
end)
minetest.register_on_dignode(function(pos)
	recalcAdjCable(pos)
end)
for xp = 0, 1 do
	for xm = 0, 1 do
		for yp = 0, 1 do
			for ym = 0, 1 do
				for zp = 0, 1 do
					for zm = 0, 1 do
						local w = 0.45
						local wt = 0.35
						local wtv = 0.15
						local fixednb={{-w, -0.5, -w, w, (1 / 16) - 0.5, w}}
						local function genbox(i)
							local function switcher(a,vFalse,vTrue) if i==a then return vTrue end return vFalse end
							local ewt = switcher(2, wt, wtv)
							table.insert(fixednb, {
							switcher(1, -ewt, -0.5),
							-0.5,
							switcher(5,-ewt, -0.5),
							switcher(0, ewt, 0.5),
							switcher(2, -13, 14) / 28,
							switcher(4, ewt, 0.5)})
						end
						if xp == 1 then genbox(0) end
						if xm == 1 then genbox(1) end
						if yp == 1 then genbox(2) end
						if zp == 1 then genbox(4) end
						if zm == 1 then genbox(5) end
						local str = getCableId(xp, xm, yp, ym, zp, zm)
						local tstr = "computech_addressbus:cable_" .. str
						local g = {dig_immediate = 2, computech_addressbus_cable = 1}
						if str=="110011" then tstr = "computech_addressbus:cable" else g.not_in_creative_inventory = 1 end
						cableIdMap[str] = tstr
						isCable[tstr] = true
						minetest.register_node(tstr, {
							description="Computech AB Ribbon " .. tstr,
							tiles = {"computech_addressbus_cable.png"},
							groups = g,
							paramtype = "light",
							drawtype = "nodebox",
							drop = "computech_addressbus:cable",
							node_box = {
								type = "fixed",
								fixed = fixednb
							},
							after_place_node = function(pos, placer, istack, pt)
								recalcCable(pos)
							end
						})
					end
				end
			end
		end
	end
end
loadfile(mp .. "/utils.lua")()
