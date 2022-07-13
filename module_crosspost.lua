-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

local Message = discordia.class.classes.Message
local CrosspostEndpoint = "/channels/%s/messages/%s/crosspost"

Module.Name = "crosspost"

function Module:CheckPermissions(member)
	return member:hasPermission(enums.permission.manageChannels)
end

function Module:OnLoaded()
	self:RegisterCommand({
		Name = "crosspost",
		Args = {
			{Name = "channel", Type = Bot.ConfigType.Channel, Optional = true},
		},
		PrivilegeCheck = function (member) return self:CheckPermissions(member) end,

		Help = "Auto Publish (Crosspost) message in Announcement Channel",
		Func = function Message:Crosspost()
  				client._api:request("POST", CrosspostEndpoint:format(self.channel.id,self.id))
		       end







