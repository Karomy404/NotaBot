local fs = require('fs')
local ffi = require('ffi')
local ssl = require('openssl')
local class = require('class')
local enums = require('enums')

local permission = enums.permission
local actionType = enums.actionType
local messageFlag = enums.messageFlag
local base64 = ssl.base64
local readFileSync = fs.readFileSync
local classes = class.classes
local isInstance = class.isInstance
local isObject = class.isObject
local insert = table.insert
local format = string.format

local band, bor, bnot, bxor = bit.band, bit.bor, bit.bnot, bit.bxor

local Resolver = {}

local istype = ffi.istype
local int64_t = ffi.typeof('int64_t')
local uint64_t = ffi.typeof('uint64_t')

local codec = {}
local ALPHANUM = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
for n, char in ALPHANUM:gmatch('()(.)') do
	codec[n - 1] = char
end

local MIN_VALUE, MAX_VALUE = 0, tonumber(bnot(0ULL))
local MIN_BASE, MAX_BASE = 2, #ALPHANUM
local MIN_BIT, MAX_BIT = 1, math.floor(math.log(MAX_VALUE, 2))

local function int(obj)
	local t = type(obj)
	if t == 'string' then
		if tonumber(obj) then
			return obj
		end
	elseif t == 'cdata' then
		if istype(int64_t, obj) or istype(uint64_t, obj) then
			return tostring(obj):match('%d*')
		end
	elseif t == 'number' then
		return format('%i', obj)
	elseif isInstance(obj, classes.Date) then
		return obj:toSnowflake()
	end
end

local function typeError(expected, received)
	return error(format('expected %s, received %s', expected, received), 2)
end

function checkNumber(obj, base, mn, mx)
	local success, n = pcall(tonumber, obj, base)
	if not success or not n then
		return typeError('number', type(obj))
	end
	if mn and n < mn then
		return typeError('minimum ' .. mn, n)
	end
	if mx and n > mx then
		return typeError('maximum ' .. mx, n)
	end
	return n
end

function checkInteger(obj, base, mn, mx)
	local success, n = pcall(tonumber, obj, base)
	if not success or not n then
		return typeError('integer', type(obj))
	end
	if n % 1 ~= 0 then
		return typeError('integer', n)
	end
	if mn and n < mn then
		return typeError('minimum ' .. mn, n)
	end
	if mx and n > mx then
		return typeError('maximum ' .. mx, n)
	end
	return n
end

local function checkBase(base)
	return checkInteger(base, 10, MIN_BASE, MAX_BASE)
end

local function checkValueRaw(value, base)
	return checkInteger(value, base, MIN_VALUE, MAX_VALUE)
end

local function str2int64(str, base)

	local i = 1
	local n = 0ULL
	local neg = false
	base = base or 10

	str = str:match('^%s*(.-)%s*$')

	if str:sub(i, i) == '-' then
		neg = true
		i = i + 1
	elseif str:sub(i, i) == '+' then
		i = i + 1
	end

	local s = #str
	repeat
		local digit = tonumber(str:sub(i, i), base)
		if not digit then
			return nil
		end
		n = n * base + digit
		i = i + 1
	until i > s

	return neg and -n or n

end


function Resolver.userId(obj)
	if isObject(obj) then
		if isInstance(obj, classes.User) then
			return obj.id
		elseif isInstance(obj, classes.Member) then
			return obj.user.id
		elseif isInstance(obj, classes.Message) then
			return obj.author.id
		elseif isInstance(obj, classes.Guild) then
			return obj.ownerId
		end
	end
	return int(obj)
end

function Resolver.messageId(obj)
	if isInstance(obj, classes.Message) then
		return obj.id
	end
	return int(obj)
end

function Resolver.channelId(obj)
	if isInstance(obj, classes.Channel) then
		return obj.id
	end
	return int(obj)
end

function Resolver.roleId(obj)
	if isInstance(obj, classes.Role) then
		return obj.id
	end
	return int(obj)
end

function Resolver.emojiId(obj)
	if isInstance(obj, classes.Emoji) then
		return obj.id
	elseif isInstance(obj, classes.Reaction) then
		return obj.emojiId
	elseif isInstance(obj, classes.Activity) then
		return obj.emojiId
	end
	return int(obj)
end

function Resolver.guildId(obj)
	if isInstance(obj, classes.Guild) then
		return obj.id
	end
	return int(obj)
end

function Resolver.entryId(obj)
	if isInstance(obj, classes.AuditLogEntry) then
		return obj.id
	end
	return int(obj)
end

function Resolver.messageIds(objs)
	local ret = {}
	if isInstance(objs, classes.Iterable) then
		for obj in objs:iter() do
			insert(ret, Resolver.messageId(obj))
		end
	elseif type(objs) == 'table' then
		for _, obj in pairs(objs) do
			insert(ret, Resolver.messageId(obj))
		end
	end
	return ret
end

function Resolver.roleIds(objs)
	local ret = {}
	if isInstance(objs, classes.Iterable) then
		for obj in objs:iter() do
			insert(ret, Resolver.roleId(obj))
		end
	elseif type(objs) == 'table' then
		for _, obj in pairs(objs) do
			insert(ret, Resolver.roleId(obj))
		end
	end
	return ret
end

function Resolver.emoji(obj)
	if isInstance(obj, classes.Emoji) then
		return obj.hash
	elseif isInstance(obj, classes.Reaction) then
		return obj.emojiHash
	elseif isInstance(obj, classes.Activity) then
		return obj.emojiHash
	end
	return tostring(obj)
end

function Resolver.color(obj)
	if isInstance(obj, classes.Color) then
		return obj.value
	end
	return tonumber(obj)
end

function Resolver.permissions(obj)
	local t = type(obj)
	if t == 'number' then
		return checkValueRaw(obj, base) + 0ULL
	elseif t == 'string' then
		checkValueRaw(obj, base)
		return str2int64(obj, base)
	elseif t == 'cdata' then
		checkValueRaw(obj, base)
		if base == nil or base == 10 then
			return obj
		else
			return str2int64(tostring(obj:match('%d*'), base))
		end
	elseif t == 'table' then
		if isInstance(obj, classes.Permissions) then
			return obj.value
		else
			local n = 0ULL
			for _, v in pairs(obj) do
				n = bor(n, checkValue(v, base))
			end
			return n
		end
	end

	return nil
end

function Resolver.permission(obj)
	local t = type(obj)
	local n = nil
	if t == 'string' then
		n = permission[obj]
	elseif t == 'cdata' then
		n = permission(obj) and obj
	elseif t == 'number' then
		n = permission(obj + 0ULL) and obj
	end
	return n
end

function Resolver.actionType(obj)
	local t = type(obj)
	local n = nil
	if t == 'string' then
		n = actionType[obj]
	elseif t == 'number' then
		n = actionType(obj) and obj
	end
	return n
end

function Resolver.messageFlag(obj)
	local t = type(obj)
	local n = nil
	if t == 'string' then
		n = messageFlag[obj]
	elseif t == 'number' then
		n = messageFlag(obj) and obj
	end
	return n
end

function Resolver.base64(obj)
	if type(obj) == 'string' then
		if obj:find('data:.*;base64,') == 1 then
			return obj
		end
		local data, err = readFileSync(obj)
		if not data then
			return nil, err
		end
		return 'data:;base64,' .. base64(data)
	end
	return nil
end

return Resolver
