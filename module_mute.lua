-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums
local bit = require("bit")

Module.Name = "mute"

function Module:GetConfigTable()
	return {
		{
			Array = true,
			Name = "AuthorizedRoles",
			Description = "Roles allowed to use mute commands",
			Type = bot.ConfigType.Role,
			Default = {}
		},
		{
			Name = "DefaultMuteDuration",
			Description = "Default mute duration if no duration is set",
			Type = bot.ConfigType.Duration,
			Default = 10 * 60
		},
		{
			Name = "SendPrivateMessage",
			Description = "Should the bot try to send a private message when muting someone?",
			Type = bot.ConfigType.Boolean,
			Default = true
		},
		{
			Name = "MuteRole",
			Description = "Mute role to be applied (no need to configure its permissions)",
			Type = bot.ConfigType.Role,
			Default = ""
		}
	}
end

function Module:CheckPermissions(member)
	local config = self:GetConfig(member.guild)
	if (util.MemberHasAnyRole(member, config.AuthorizedRoles)) then
		return true
	end

	if (member:hasPermission(enums.permission.administrator)) then
		return true
	end

	return false
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "mute",
		Args = {
			{Name = "target", Type = Bot.ConfigType.Member},
			{Name = "duration", Type = Bot.ConfigType.Duration, Optional = true},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Mutes a member",
		Silent = true,
		Func = function (commandMessage, targetMember, duration, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)
			local mutedBy = commandMessage.member

			-- Duration
			if (not duration) then
				duration = config.DefaultMuteDuration
			end

			-- Reason
			if reason and #reason > 0 then
				reason = " " .. bot:Format(guild, "MUTE_REASON", reason)
			else
				reason = ""
			end

			local mutedByRole = mutedBy.highestRole
			local targetRole = targetMember.highestRole
			if (targetRole.position >= mutedByRole.position) then
				commandMessage:reply(bot:Format(guild, "MUTE_NOTAUTHORIZED"))
				return
			end

			if (config.SendPrivateMessage) then
				local durationText
				if (duration > 0) then
					durationText = "\n" .. bot:Format(guild, "MUTE_YOU_WILL_BE_UNMUTED_IN", util.DiscordRelativeTime(duration))
				else
					durationText = ""
				end

				local privateChannel = targetMember:getPrivateChannel()
				if (privateChannel) then
					privateChannel:send(bot:Format(guild, "MUTE_PRIVATE_MESSAGE", guild.name, mutedBy.user.mentionString, reason, durationText))
				end
			end

			local success, err = self:Mute(guild, targetMember.id, duration)
			if (success) then
				local durationText
				if (duration > 0) then
					durationText = "\n" .. bot:Format(guild, "MUTE_THEY_WILL_BE_UNMUTED_IN", util.DiscordRelativeTime(duration))
				else
					durationText = ""
				end

				commandMessage:reply(bot:Format(guild, "MUTE_GUILD_MESSAGE", mutedBy.name, targetMember.tag, reason, durationText))
			else
				commandMessage:reply(bot:Format(guild, "MUTE_MUTE_FAILED", targetMember.tag, err))
			end
		end
	})

	self:RegisterCommand({
		Name = "unmute",
		Args = {
			{Name = "target", Type = Bot.ConfigType.User},
			{Name = "reason", Type = Bot.ConfigType.String, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Unmutes a member",
		Silent = true,
		Func = function (commandMessage, targetUser, reason)
			local guild = commandMessage.guild
			local config = self:GetConfig(guild)

			-- Reason
			if reason and #reason > 0 then
				reason = " " .. bot:Format(guild, "MUTE_REASON", reason)
			else
				reason = ""
			end

			if (config.SendPrivateMessage) then
				local privateChannel = targetUser:getPrivateChannel()
				if (privateChannel) then
					privateChannel:send(bot:Format(guild, "MUTE_UNMUTE_MESSAGE", guild.name, commandMessage.member.mentionString, reason))
				end
			end

			local success, err = self:Unmute(guild, targetUser.id)
			if (success) then
				commandMessage:reply(bot:Format(guild, "MUTE_UNMUTE_GUILD_MESSAGE", commandMessage.member.name, targetUser.tag, reason))
			else
				commandMessage:reply(bot:Format(guild, "MUTE_UNMUTE_FAILED", targetUser.tag, err))
			end
		end
	})

	return true
end

function Module:OnEnable(guild)
	local config = self:GetConfig(guild)

	local muteRole = config.MuteRole and guild:getRole(config.MuteRole) or nil
	if (not muteRole) then
		return false, "Invalid mute role (check your configuration)"
	end

	self:LogInfo(guild, "Checking mute role permission on all channels...")

	for _, channel in pairs(guild.textChannels) do
		self:CheckTextMutePermissions(channel)
	end

	for _, channel in pairs(guild.voiceChannels) do
		self:CheckVoiceMutePermissions(channel)
	end

	local persistentData = self:GetPersistentData(guild)
	persistentData.MutedUsers = persistentData.MutedUsers or {}

	local data = self:GetData(guild)
	data.UnmuteTimers = {}

	for userId, unmuteTimestamp in pairs(persistentData.MutedUsers) do
		self:RegisterUnmute(guild, userId, unmuteTimestamp)
	end

	return true
end

function Module:OnDisable(guild)
	local data = self:GetData(guild)
	if (data.UnmuteTimers) then
		for userId, timer in pairs(data.UnmuteTimers) do
			timer:Stop()
		end
	end
end

function Module:CheckTextMutePermissions(channel)
	local config = self:GetConfig(channel.guild)
	local mutedRole = channel.guild:getRole(config.MuteRole)
	if (not mutedRole) then
		self:LogError(channel.guild, "Invalid muted role")
		return
	end

	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	assert(permissions)

	local deniedPermissions = permissions:getDeniedPermissions()
	-- :enable here just sets the bit, disabling the permissions
	deniedPermissions:enable(enums.permission.addReactions, enums.permission.sendMessages, enums.permission.usePublicThreads, enums.permission.sendMessagesInThreads)

	if permissions:getAllowedPermissions() ~= discordia.Permissions() or permissions:getDeniedPermissions() ~= deniedPermissions then
		permissions:setPermissions('0', deniedPermissions)
	end
end

function Module:CheckVoiceMutePermissions(channel)
	local config = self:GetConfig(channel.guild)
	local mutedRole = channel.guild:getRole(config.MuteRole)
	if (not mutedRole) then
		self:LogError(channel.guild, "Invalid muted role")
		return
	end


	local permissions = channel:getPermissionOverwriteFor(mutedRole)
	assert(permissions)

	local deniedPermissions = permissions:getDeniedPermissions()
	-- :enable here just sets the bit, disabling the permissions
	deniedPermissions:enable(enums.permission.speak)

	if permissions:getAllowedPermissions() ~= discordia.Permissions() or permissions:getDeniedPermissions() ~= deniedPermissions then
		permissions:setPermissions('0', deniedPermissions)
	end
end

function Module:Mute(guild, userId, duration)
	local config = self:GetConfig(guild)
	local member = guild:getMember(userId)
	if (not member) then
		return false, bot:Format(guild, "MUTE_ERROR_NOT_PART_OF_GUILD", "<@" .. userId .. ">")
	end

	local success, err = member:addRole(config.MuteRole)
	if (not success) then
		self:LogError(guild, "failed to mute %s: %s", member.tag, err)
		return false, err
	end

	local persistentData = self:GetPersistentData(guild)
	local unmuteTimestamp = duration > 0 and os.time() + duration or 0
		
	persistentData.MutedUsers[userId] = unmuteTimestamp
	self:RegisterUnmute(guild, userId, unmuteTimestamp)

	return true
end

function Module:RegisterUnmute(guild, userId, timestamp)
	if (timestamp ~= 0) then
		local data = self:GetData(guild)
		local timer = data.UnmuteTimers[userId]
		if (timer) then
			timer:Stop()
		end

		data.UnmuteTimers[userId] = Bot:ScheduleTimer(timestamp, function () self:Unmute(guild, userId) end)
	end
end

function Module:Unmute(guild, userId)
	local config = self:GetConfig(guild)

	local member = guild:getMember(userId)
	if (member) then
		local success, err = member:removeRole(config.MuteRole)
		if (not success) then
			self:LogError(guild, "Failed to unmute %s: %s", member.tag, err)
			return false, err
		end
	end

	local data = self:GetData(guild)
	local timer = data.UnmuteTimers[userId]
	if (timer) then
		timer:Stop()

		data.UnmuteTimers[userId] = nil
	end

	local persistentData = self:GetPersistentData(guild)
	persistentData.MutedUsers[userId] = nil

	return true
end

function Module:OnChannelCreate(channel)
	if (channel.type == enums.channelType.text) then
		self:CheckTextMutePermissions(channel)
	elseif (channel.type == enums.channelType.voice) then
		self:CheckVoiceMutePermissions(channel)
	end
end

function Module:OnMemberJoin(member)
	local guild = member.guild

	local config = self:GetConfig(guild)
	local persistentData = self:GetPersistentData(guild)
	if (persistentData.MutedUsers[member.id]) then
		local success, err = member:addRole(config.MuteRole)
		if (not success) then
			self:LogError(guild, "failed to apply mute role to %s: %s", member.tag, err)
		end
	end
end
