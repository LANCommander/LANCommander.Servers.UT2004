//=============================================================================
// LCStatsSocket: one TCP connection to ut2004-stats-bridge.
//=============================================================================
class LCStatsSocket extends TcpLink;

var LCStatsClient Client;

function bool Begin(string Host, int Port)
{
	local IpAddr Addr;

	if (!StringToIpAddr(Host, Addr))
	{
		log("LCServer: the stats bridge host must be an IP address, not" @ Host);
		return false;
	}
	Addr.Port = Port;

	LinkMode = MODE_Text;
	ReceiveMode = RMODE_Event;

	if (BindPort() == 0)
		return false;

	return Open(Addr);
}

event Opened()
{
	if (Client != None)
		Client.SocketOpened(self);
}

event Closed()
{
	if (Client != None)
		Client.SocketClosed(self);
}

// The bridge sends nothing
event ReceivedText(string Text);

defaultproperties
{
	RemoteRole=ROLE_None
}
