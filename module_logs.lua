-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "logs"

function Module:GetConfigTable()
	return {
		{
			Name = "DeletedMessageChannel",
			Description = "Where deleted messages should be logged",
			Type = bot.ConfigType.Channel,
			Optional = true
		},
        {
            Name = "IgnoredDeletedMessageChannels",
            Description = "Messages deleted in those channels will not be logged",
            Type = bot.ConfigType.Channel,
            Array = true,
            Default = {}
        },
		{
			Global = true,
			Name = "PersistentMessageCacheSize",
			Description = "How many of the last messages of every text channel should stay in bot memory?",
			Type = bot.ConfigType.Integer,
			Default = 50
		},
	}
end

function Module:OnEnable(guild)
    local data = self:GetData(guild)

    -- Keep a reference to the last X messages of every text channel
    local messageCacheSize = self.GlobalConfig.PersistentMessageCacheSize
    data.cachedMessages = {}

	coroutine.wrap(function ()
        for _, channel in pairs(guild.textChannels) do
            data.cachedMessages[channel.id] = Bot:FetchChannelMessages(channel, nil, messageCacheSize, true)
        end
    end)()

	return true
end

function Module:OnChannelDelete(channel)
	local guild = channel.guild
    if not guild then
        return
    end

    local data = self:GetData(guild)
    data.cachedMessages[channel.id] = nil
end

function Module:OnMessageDelete(message)
    local guild = message.guild
    local config = self:GetConfig(guild)
    
    if table.search(config.IgnoredDeletedMessageChannels, message.channel.id) then
        return
    end

    local deletedMessageChannel = config.DeletedMessageChannel
    if not deletedMessageChannel then
        return
    end

    local logChannel = guild:getChannel(deletedMessageChannel)
    if not logChannel then
        self:LogWarning(guild, "Deleted message log channel %s no longer exists", deletedMessageChannel)
        return
    end

    local desc = "🗑️ **Deleted message - sent by " .. message.author.mentionString .. " in " .. message.channel.mentionString .. "**\n"

	local embed = Bot:BuildQuoteEmbed(message, { initialContentSize = #desc })
    embed.description = desc .. (embed.description or "")
	embed.footer = {
		text = string.format("Author ID: %s | Message ID: %s", message.author.id, message.id)
	}
    embed.timestamp = discordia.Date():toISO('T', 'Z')

	logChannel:send({
        embed = embed
	})
end

function Module:OnMessageDeleteUncached(channel, messageId)
    local guild = channel.guild
    local config = self:GetConfig(guild)

    if table.search(config.IgnoredDeletedMessageChannels, channel.id) then
        return
    end

    local deletedMessageChannel = config.DeletedMessageChannel
    if not deletedMessageChannel then
        return
    end

    local logChannel = guild:getChannel(deletedMessageChannel)
    if not logChannel then
        self:LogWarning(guild, "Deleted message log channel %s no longer exists", deletedMessageChannel)
        return
    end

	logChannel:send({
        embed = {
            description = "🗑️ **Deleted message (uncached) - sent by <unknown> in " .. channel.mentionString .. "**",
            footer = {
                text = string.format("Message ID: %s", messageId)
            },
            timestamp = discordia.Date():toISO('T', 'Z')
        }
	})
end

function Module:OnMessageCreate(message)
	local guild = message.guild
    if not guild then
        return
    end

    local data = self:GetData(guild)
    local cachedMessages = data.cachedMessages[message.channel.id]
    if not cachedMessages then
        cachedMessages = {}
        data.cachedMessages[message.channel.id] = cachedMessages
    end

    -- Remove oldest message from permanent cache and add the new message
    table.insert(cachedMessages, message)

    local messageCacheSize = self.GlobalConfig.PersistentMessageCacheSize
    while #cachedMessages > messageCacheSize do
        table.remove(cachedMessages, 1)
    end
end
