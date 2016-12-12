-- computech forth machine block

local luaforth = dofile(minetest.get_modpath("computech_machine_forth") .. "/luaforth.lua")
local tremove = table.remove

-- Variables
local fm_timer = 0.1 -- 10Hz

-- IE
local ie, req_ie = _G, minetest.request_insecure_environment
if req_ie then ie = req_ie() end
if not ie then
	error("computech_machine_forth requires access to insecure functions. Please add computech_machine_forth to your secure.trusted_mods.")
end

-- environment!
local function push(stack, x)
	stack[#stack + 1] = x
end
local function pop(stack)
	if #stack == 0 then error("Stack underflow!", 0) end
	return tremove(stack)
end

local function rebuild_env(env, pos)
	env["pos"] = pos

	-- digiline stuff
	env["digiline-send"] = {
		_fn = function(_, _, chan, msg)
			print("[computech_machine_forth] D: digiline-send "..chan.." "..msg)
			digiline:receptor_send(pos, digiline.rules.default, tostring(chan), msg)
		end,
		_args = 2,
	}
	env["digiline-recv"] = {
		_fn = function()
			-- trick, since everything is event based, we just halt execution until
			-- a digiline event arrives
			local meta = minetest.get_meta(pos)
			meta:set_int("waitingfordigi", 1)
			local timer = minetest.get_node_timer(pos)
			timer:stop()
		end,
	}
	return env
end

local function construct_env(pos)
	return {
		-- comments
		["\\"] = {
			_fn = function() end,
			_parse = "line",
		},
		-- strings
		["s'"] = {
			_fn = function(_, _, str)
				return str
			end,
			_parse = "endsign",
			_endsign = "'",
		},
		-- arithmetic
		["+"] = {
			_fn = function(_, _, no1, no2)
				return no1 + no2
			end,
			_args = 2,
		},
		["-"] = {
			_fn = function(_, _, no1, no2)
				return no2 - no1
			end,
			_args = 2,
		},
		["*"] = {
			_fn = function(_, _, no1, no2)
				return no1 * no2
			end,
			_args = 2,
		},
		["/"] = {
			_fn = function(_, _, no1, no2)
				return no2 / no1
			end,
			_args = 2,
		},
		-- helpers
		["swap"] = {
			_fn = function(_, _, no1, no2)
				return no1, no2 -- even though this line does not show it, it'll end up reversed on the stack.
			end,
			_args = 2,
		},
	}
end

-- construct
local function reset(pos, code)
	print("[computech_machine_forth] D: machine reset")
	local meta = minetest.get_meta(pos)
	meta:set_string("stack", computech.msgpack.iepack(ie, {}))
	code = code or "s' Hello World' s' output' digiline_send"
	meta:set_string("code", code)
	local env = construct_env(pos)
	env = rebuild_env(env, pos)
	meta:set_string("env", computech.msgpack.iepack(ie, env))
	local insts = luaforth.parse(code, env)
	print("[computech_machine_forth] D: Parsed insts, "..tostring(insts))
	meta:set_string("insts", computech.msgpack.iepack(ie, insts))
	meta:set_int("ipos", 1)
	meta:set_string("waitingfor", "")
	meta:set_string("formspec", "size[10,8]"..
		"textarea[0-2,0.6;10.2,5;code;;"..minetest.formspec_escape(code).."]"..
		"button[3.75,6;2.5,1;load;Load]"..
		"button_exit[9.72,-0.25;0.425,04;exit;Exit]")

	local timer = minetest.get_node_timer(pos)
	if timer:is_started() then
		timer:stop()
	end
	timer:start(fm_timer) -- 10Hz, maybe.
end

local function on_receive_fields(pos, _, fields, sender)
	if fields.code == nil then return end
	reset(pos, fields.code)
end

local function restart(pos)
	local meta = minetest.get_meta(pos)
	local timer = minetest.get_node_timer(pos)
	print("[computech_machine_forth] D: Restart")
	meta:set_int("ipos", 1)
	meta:set_string(computech.msgpack.iepack(ie, {}))
	timer:start(fm_timer)
end

-- tick and events
local function on_timer(pos)
	print("[computech_machine_forth] D: Timer")
	local meta = minetest.get_meta(pos)
	-- get stuff
	local stack = computech.msgpack.ieunpack(ie, meta:get_string("stack"))
	local insts = computech.msgpack.ieunpack(ie, meta:get_string("insts"))
	local ipos = meta:get_int("ipos")
	local env = computech.msgpack.ieunpack(ie, meta:get_string("env"))
	local waitingfordigi = meta:get_int("waitingfordigi")

	-- run stuff
	if waitingfordigi == 0 then -- not waiting for anything
		local success, new_stack, new_env
		local inst = insts[ipos]
		if inst then
			local timer = minetest.get_node_timer(pos)
			print("[computech_machine_forth] D: Running inst")
			success, new_stack, new_env = pcall(luaforth.eval_inst, inst, env, stack)
			if not success then
				print("[computech_machine_forth] D: Fail")
				-- do something with the error.
				timer:stop()
				meta:set_string("lasterror", new_stack)
				print("[computech_machine_forth] I: Machine at "..computech.strutils.stringify_pos(pos).." errored: "..tostring(new_stack))
				return
			end
			print("[computech_machine_forth] D: Done running inst.")
			-- set stuff
			meta:set_string("stack", computech.msgpack.iepack(ie, new_stack))
			meta:set_int("ipos", ipos + 1)
			meta:set_string("env", computech.msgpack.iepack(ie, new_env))
			print("[computech_machine_forth] D: Set new stack and env. What is happening?!")
			if meta:get_int("waitfordigi") == 0 then
				timer:start(fm_timer) -- 1Hz for now.
			end
		else -- loop back
			print("[computech_machine_forth] D: Resetting?]")
			restart(pos)
			return
		end
	end
end

local function on_digiline(pos, node, channel, msg)
	print("[computech_machine_forth] D: digiline event")
	-- get some stuff
	local meta = minetest.get_meta(pos)
	local waitingfordigi = meta:get_int("waitingfordigi")

	if waitingfordigi == 1 then
		local stack = computech.msgpack.ieunpack(ie, meta:get_string("stack"))
		push(stack, msg)
		push(stack, channel)
		meta:set_string("stack", computech.msgpack.iepack(ie, stack))
		meta:set_int("waitingfordigi", 0)
		local timer = minetest.get_node_timer(pos)
		timer:start(fm_timer)
	end
end

minetest.register_node("computech_machine_forth:basic_forth_machine", {
	description = "CompuTech Forth Machine",
	on_construct = reset,
	on_receive_fields = on_receive_fields,
	on_timer = on_timer,
	digiline = {
		receptor = {},
		effector = {
			action = on_digiline,
		},
	},
})

