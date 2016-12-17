-- Better node timers!
-- (Does use actual node timers, for re-registration.
--  If a node is replaced within a tick with one of the same type,
--   then the node will still receive timer ticks.
--  So assume you may receive unexpected on_timer calls.)

-- fm_registry["1:2:3"] = {{x=1,y=1,z=1}, "node:type", function(pos) end, interval, ofsnow}
local bettertimers = {}
local fm_registry = {}
local function fm_position(pos)
	return pos.x .. ":" .. pos.y .. ":" .. pos.z
end
function bettertimers.register(pos, nt, func, time)
	fm_registry[fm_position(pos)] = {pos, nt, func, time, 0}
end
function bettertimers.deregister(pos)
	fm_registry[fm_position(pos)] = nil
end
-- Use as your on_timer function to maintain a registration.
function bettertimers.create_on_timer(nt, func, time)
	return function (pos)
		if fm_registry[fm_position(pos)] then
			if fm_registry[2] == nt then
				if fm_registry[3] == func and fm_registry[4] == time then
					-- Timer is already running w/ correct settings.
					return
				end
			end
		end
		bettertimers.register(pos, nt, func, time)
		return true
	end
end
local lastTimeframe = nil
minetest.register_globalstep(function(dt)
	local nextTimeframe = minetest.get_us_time() / 1000000
	if not lastTimeframe then
		lastTimeframe = nextTimeframe
	end
	dt = nextTimeframe - lastTimeframe
	lastTimeframe = nextTimeframe
	local p = {}
	for k, v in pairs(fm_registry) do
		local t = p[v[2]] or 0
		p[v[2]] = t + 1
	end
	for k, v in pairs(fm_registry) do
		local n = minetest.get_node(v[1])
		if (not n) or (n.name ~= v[2]) then
			bettertimers.deregister(v[1])
		else
			v[5] = v[5] + dt
			if v[5] > v[4] then
				v[5] = v[5] - v[4]
				if v[5] > v[4] then
					v[5] = 0
					print("Warning: computech_base bettertimers hit two ticks in one step. Reduce system usage. " .. dt)
				end
				v[3](v[1], p[v[2]])
			end
		end
	end
end)

return bettertimers
