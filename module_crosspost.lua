local Message = discordia.class.classes.Message
local CrosspostEndpoint = "/channels/%s/messages/%s/crosspost"

function Message:Crosspost()
  client._api:request("POST", CrosspostEndpoint:format(self.channel.id,self.id))
end
