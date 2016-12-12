-- msgpack wrapper with all features needed

-- lua-MessagePack from fperrad on github.
local msgpack = dofile(computech.modpath_base .. "/thirdparty/MessagePack.lua")

local ie

-- Helpers
local function getallupvals(f)
	local i = 1
	local r = {}
	while true do
		local n, v = ie.debug.getupvalue(f, i)
		if not n then
			if r == {} then
				return nil
			end
			return r
		end
		if n ~= "_ENV" then
			r[i] = {name=n, value=v}
		end
		i = i + 1
	end
end

local function setallupvals(f, vals)
	for i, pair in pairs(vals) do
		ie.debug.setupvalue(f, i, pair["value"])
	end
end

-- Our tweaks.
-- Support more lua types, but at the cost of compatibility with non-computech msgpack things.

-- Functions

msgpack.packers['_function'] = function(buffer, fn)
	return msgpack.packers['ext'](buffer, 7, assert(string.dump(fn)))
end
msgpack.packers['function'] = function(buffer, fn)
	local upvals = getallupvals(fn)
	if upvals then
		local buf = {}
		msgpack.packers['_function'](buf, fn)
		msgpack.packers['table'](buf, upvals)
		msgpack.packers['ext'](buffer, 8, table.concat(buf))
	else
		msgpack.packers['_function'](buffer, fn)
	end
end

-- Tables
msgpack.packers['table'] = function(buffer, t)
	local mt = getmetatable(t)
	if mt then
		local buf = {}
		msgpack.packers['_table'](buf, t)
		msgpack.packers['table'](buf, mt)
		msgpack.packers['ext'](buffer, 42, table.concat(buf))
	else
		msgpack.packers['_table'](buffer, t)
	end
end

-- Unpacker for both
msgpack.build_ext = function (tag, data)
	if tag == 7 and ie then -- Function
		return assert(ie.loadstring(data))
	elseif tag == 8 and ie then -- Function with upvals
		local f = msgpack.unpacker(data)
		local _, fn = f()
		local _, upvals = f()
		setallupvals(fn, upvals)
		return fn
	elseif tag == 42 then -- Table
		local f = msgpack.unpacker(data)
		local _, t = f()
		local _, mt = f()
		return setmetatable(t, mt)
	end
end

-- IE helper
function msgpack.iepack(new_ie, ...)
	ie = new_ie
	return msgpack.pack(...)
end
function msgpack.ieunpack(new_ie, ...)
	ie = new_ie
	return msgpack.unpack(...)
end

return msgpack
