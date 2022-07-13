-- Copyright (C) 2018 Jérôme Leclercq
-- This file is part of the "Not a Bot" application
-- For conditions of distribution and use, see copyright notice in LICENSE

local client = Client
local discordia = Discordia
local bot = Bot
local enums = discordia.enums

Module.Name = "crosspost"

function Module:CheckPermissions(member)
	return member:hasPermission(enums.permission.manageChannels)
end

local Message = discordia.class.classes.Message
local CrosspostEndpoint = "/channels/%s/messages/%s/crosspost"

function Message:Crosspost()
  client._api:request("POST", CrosspostEndpoint:format(self.channel.id,self.id))
end
