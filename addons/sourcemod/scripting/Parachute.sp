/*******************************************************************************

    SM Parachute

    Version: 2.5
    Author: SWAT_88
	
    Copyright:
  
    Everybody can edit this plugin and copy this plugin.
	
    Thanks to:
  
	Greyscale
	Pinkfairie
	bl4nk
	theY4Kman
	Knagg0
	KRoT@L
	JTP10181
	
    HAVE FUN!!!

*******************************************************************************/

#include <sourcemod>
#include <sdktools>

#define PARACHUTE_VERSION 	"2.5"

char g_sModelName[PLATFORM_MAX_PATH];

ConVar g_cvParachuteFallSpeed;
ConVar g_cvParachuteLinear;
ConVar g_cvParachuteDecrease;

int g_iVelocity = -1;
int g_iParachuteEntity[MAXPLAYERS+1];

bool g_bFallSpeed[MAXPLAYERS +1] = {false, ...};
bool g_bInUse[MAXPLAYERS+1] = {false, ...};
bool g_bHasParachuteModel[MAXPLAYERS+1] = {false, ...};

public Plugin myinfo =
{
	name = "SM Parachute",
	author = "SWAT_88",
	description = "Adds a parachute with low gravity when you hold the use key",
	version = PARACHUTE_VERSION,
	url = "http://www.sourcemod.net/"
};

public OnPluginStart()
{
	g_cvParachuteFallSpeed = CreateConVar("sm_parachute_fallspeed", "100", "Speed of the fall when you use the parachute");
	g_cvParachuteLinear = CreateConVar("sm_parachute_linear", "1", "0: disables linear fallspeed - 1: enables it");
	g_cvParachuteDecrease = CreateConVar("sm_parachute_decrease", "50", "0: dont use Realistic velocity-decrease - x: sets the velocity-decrease");

	g_iVelocity = FindSendPropInfo("CBasePlayer", "m_vecVelocity[0]");

	HookEvent("player_death", PlayerDeath);

	AutoExecConfig(true);
}

/*******************************************************************************

    Currently supports one parachute model at a time, maybe update later or not.

*******************************************************************************/

public void OnMapStart()
{
	PrecacheModels();
	ReadDownloadsFile();    
}

void PrecacheModels()
{
	char KvPath[128];
	BuildPath(Path_SM, KvPath, sizeof(KvPath), "configs/parachute_models.cfg");
	KeyValues Kv = new KeyValues("Models");
	Kv.ImportFromFile(KvPath);
	{
		Kv.JumpToKey("Parachute", false);
		Kv.GetString("model", g_sModelName, sizeof(g_sModelName));
		PrecacheModel(g_sModelName);
		Kv.Rewind();
	}
	delete Kv;	
}

void ReadDownloadsFile()
{
	char FilePath[128];
	BuildPath(Path_SM, FilePath, sizeof(FilePath), "configs/parachute_downloads.cfg");
	Handle DlFile = OpenFile(FilePath, "r");
	char Line[PLATFORM_MAX_PATH];
	while(!IsEndOfFile(DlFile) && ReadFileLine(DlFile, Line, sizeof(Line)))
	{
		TrimString(Line);
		AddFileToDownloadsTable(Line);
	}
	delete DlFile;
}

public void OnClientDisconnect(int client)
{
	DeleteParachute(client);
	g_bFallSpeed[client] = false;
	g_bInUse[client] = false;
}

public void PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	StopParachute(client);
}

public void OnGameFrame()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && IsPlayerAlive(client) && !IsFakeClient(client))
		{
			if(GetClientButtons(client) & IN_USE)
			{
				if(!g_bInUse[client])
				{
					g_bInUse[client] = true;
					g_bFallSpeed[client] = false;
					StartParachute(client, true);
				}
				StartParachute(client, false);
				TeleportParachute(client);
			}
			else
			{
				if(g_bInUse[client])
				{
					g_bInUse[client] = false;
					StopParachute(client);
				}
			}
			CheckClientLocation(client);
		}
	}
}

void StartParachute(int client, bool open)
{
	float g_fVelocity[3];
	float g_fFallSpeed;
	if(g_iVelocity == -1) 
	{
		return;
	}
	g_fFallSpeed = GetConVarFloat(g_cvParachuteFallSpeed) * (-1.0);
	GetEntDataVector(client, g_iVelocity, g_fVelocity);
	if(g_fVelocity[2] >= g_fFallSpeed)
	{
		g_bFallSpeed[client] = true;
	}
	if(g_fVelocity[2] < 0.0) 
	{
		if((g_bFallSpeed[client] && GetConVarInt(g_cvParachuteLinear) == 1) || GetConVarFloat(g_cvParachuteDecrease) == 0.0)
		{
			g_fVelocity[2] = g_fFallSpeed;
		}
		else
		{
			g_fVelocity[2] = g_fVelocity[2] + GetConVarFloat(g_cvParachuteDecrease);
		}
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, g_fVelocity);
		SetEntDataVector(client, g_iVelocity, g_fVelocity);
		SetEntityGravity(client, 0.1);
		if(open) 
		{
			OpenParachute(client);
		}
	}
}

void OpenParachute(int client)
{
	g_iParachuteEntity[client] = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(g_iParachuteEntity[client], "model", g_sModelName);
	SetEntityMoveType(g_iParachuteEntity[client], MOVETYPE_NOCLIP);
	DispatchSpawn(g_iParachuteEntity[client]);
	g_bHasParachuteModel[client] = true;
	TeleportParachute(client);
}

void TeleportParachute(int client)
{
	if(g_bHasParachuteModel[client] && IsValidEntity(g_iParachuteEntity[client]))
	{
		float g_fClient_Origin[3];
		float g_fClient_Angles[3];
		float g_fParachute_Angles[3];
		GetClientAbsOrigin(client, g_fClient_Origin);
		GetClientAbsAngles(client, g_fClient_Angles);
		g_fParachute_Angles[1] = g_fClient_Angles[1];
		TeleportEntity(g_iParachuteEntity[client], g_fClient_Origin, g_fParachute_Angles, NULL_VECTOR);
	}
}

void StopParachute(int client)
{
	SetEntityGravity(client, 1.0);
	g_bInUse[client] = false;
	g_bFallSpeed[client] = false;
	DeleteParachute(client);
}

void DeleteParachute(int client)
{
	if(g_bHasParachuteModel[client] && IsValidEntity(g_iParachuteEntity[client]))
	{
		AcceptEntityInput(g_iParachuteEntity[client], "Kill");
		g_bHasParachuteModel[client] = false;
	}
}

void CheckClientLocation(int client)
{
	float g_fSpeed[3];
	GetEntDataVector(client, g_iVelocity, g_fSpeed);
	if(g_fSpeed[2] >= 0 || (GetEntityFlags(client) & FL_ONGROUND)) 
	{
		StopParachute(client);
	}
}
