-- String utilities
-- Basic, but Useful things like trimming or splitting strings.

local strutils = {}

-- localize functions
local strmatch, strfind, strsub, strfmt = string.match, string.find, string.sub, string.format

-- trim
function strutils.trim(str)
	local from = strmatch("^%s*()")
	return from > #s and "" or strmatch(".*%S", from)
end

-- from http://lua-users.org/wiki/SplitJoin lightly tweaked
function strutils.split(str, sSeparator, nMax, bRegexp)
	assert(sSeparator ~= '')
	assert(nMax == nil or nMax >= 1)

	local aRecord = {}

	if #str > 0 then
		local bPlain = not bRegexp
		nMax = nMax or -1

		local nField, nStart = 1, 1
		local nFirst, nLast = strfind(str, sSeparator, nStart, bPlain)
		while nFirst and nMax ~= 0 do
			aRecord[nField] = strsub(str, nStart, nFirst-1)
			nField = nField+1
			nStart = nLast+1
			nFirst,nLast = strfind(str, sSeparator, nStart, bPlain)
			nMax = nMax-1
		end
		aRecord[nField] = strsub(str, nStart)
	end

	return aRecord
end

-- stringify pos object
local stringify_pos_fmt = '(%u,%u,%u)'
function strutils.stringify_pos(pos)
	return strfmt(stringify_pos_fmt, pos.x, pos.y, pos.z)
end

return strutils
