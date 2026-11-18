//=============================================================================
// LCStatsClient: the line queue to ut2004-stats-bridge. Lines wait here until
// a connection is up. Each connection attempt is a fresh LCStatsSocket. After
// a reconnect, LCGameStats re-sends the game's start and roster first, so the
// bridge picks the match up where it was.
//=============================================================================
class LCStatsClient extends Info;

const MaxQueue = 4000;
const LinesPerTick = 64;
const ConnectTimeout = 5.0;
const RetryDelay = 5.0;

var string Host;
var int    Port;

var LCGameStats   Stats;
var LCStatsSocket Socket;
var array<string> Queue;

var bool  bConnected;
var bool  bEverConnected;
var float AttemptStarted;
var float NextAttempt;
var bool  bWarnedFull;

function Setup(string InHost, int InPort)
{
	Host = InHost;
	Port = InPort;
	Connect();
	SetTimer(0.1, true);
}

function SendLine(string Line)
{
	if (Queue.Length >= MaxQueue)
	{
		if (!bWarnedFull)
			log("LCServer: the stats bridge at" @ Host $ ":" $ Port @ "isn't taking lines; dropping new ones");
		bWarnedFull = true;
		return;
	}
	Queue[Queue.Length] = Line;
}

// Puts lines in front of everything queued (the re-sent game start)
function PrependLines(array<string> Lines)
{
	local int i;

	Queue.Insert(0, Lines.Length);
	for (i = 0; i < Lines.Length; i++)
		Queue[i] = Lines[i];
}

function Connect()
{
	if (Socket != None)
		Socket.Destroy();

	Socket = Spawn(class'LCStatsSocket', self);
	Socket.Client = self;
	AttemptStarted = Level.TimeSeconds;
	if (!Socket.Begin(Host, Port))
	{
		Socket.Destroy();
		Socket = None;
		NextAttempt = Level.TimeSeconds + RetryDelay;
	}
}

function SocketOpened(LCStatsSocket S)
{
	if (S != Socket)
		return;

	bConnected = true;
	bWarnedFull = false;
	log("LCServer: connected to the stats bridge at" @ Host $ ":" $ Port);

	if (bEverConnected && Stats != None && !Stats.bDeleteMe)
		Stats.Resync();
	bEverConnected = true;
}

function SocketClosed(LCStatsSocket S)
{
	if (S != Socket)
		return;

	if (bConnected)
		log("LCServer: lost the stats bridge connection; reconnecting");
	bConnected = false;
	Socket = None;
	S.Destroy();
	NextAttempt = Level.TimeSeconds + RetryDelay;
}

event Timer()
{
	local int i, N;

	if (bConnected && Socket != None && !Socket.IsConnected())
		SocketClosed(Socket);

	if (!bConnected)
	{
		if (Socket != None && Level.TimeSeconds - AttemptStarted > ConnectTimeout)
		{
			Socket.Destroy();
			Socket = None;
			NextAttempt = Level.TimeSeconds + RetryDelay;
		}
		if (Socket == None && Level.TimeSeconds >= NextAttempt)
			Connect();
		return;
	}

	N = Min(Queue.Length, LinesPerTick);
	for (i = 0; i < N; i++)
		Socket.SendText(Queue[i] $ Chr(10));
	if (N > 0)
		Queue.Remove(0, N);
}

event Destroyed()
{
	if (Socket != None)
	{
		Socket.Close();
		Socket.Destroy();
	}
	Super.Destroyed();
}

defaultproperties
{
	RemoteRole=ROLE_None
}
