-- Digilines-based communication module

if not digiline then
	error("Digilines not found. Maybe you didn't install it?")
end

local com = {}

-- Helpers for digiline sending and receiving
local _wrap_reply = function(self, message)
	return digiline:receptor_send(self.pos, digiline.rules.default, self.channel, message)
end
local _wrap_send = function(self, chan, message)
	return digiline:receptor_send(self.pos, digiline.rules.default, chan, message)
end

function com.wrap(fn)
	-- Takes an "easy-mode" function taking a single object
	-- and returns a function creating said object from it's
	-- arguments.
	return function(pos, node, channel, msg)
		local obj = {
			pos = pos,
			node = node,
			channel = channel,
			msg = msg,
			reply = _wrap_reply,
			send = _wrap_send,
		}
		return fn(obj)
	end 
end

-- Return
return com
