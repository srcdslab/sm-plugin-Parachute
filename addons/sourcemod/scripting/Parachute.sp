/*******************************************************************************
  SM Parachute - Author: SWAT_88
  Copyright: Everybody can edit this plugin and copy this plugin.

  Thanks to:
  Greyscale, Pinkfairie, bl4nk, theY4Kman, Knagg0, KRoT@L, JTP10181, Dolly132, .Rushaway
*******************************************************************************/

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <multicolors>

enum struct ParachuteInfo
{
    char name[64];
    char model[PLATFORM_MAX_PATH];
    float z;
    float angles[3];
}

enum struct Parachute
{
    int entRef;
    bool active;
    bool fallSpeed;
    float z;
    float angles[3];

    void Reset()
    {
        this.entRef = INVALID_ENT_REFERENCE;
        this.active = false;
        this.fallSpeed = false;
        this.z = 0.0;
        this.angles[0] = this.angles[1] = this.angles[2] = 0.0;
    }

	void SetActive()
	{
		this.active = true;
		this.fallSpeed = false;
	}

	void SetInactive()
	{
		this.active = false;
		this.fallSpeed = false;
	}

    int GetEntity()
    {
        int ent = EntRefToEntIndex(this.entRef);
        return (ent > 0 && IsValidEntity(ent)) ? ent : -1;
    }
}

Parachute g_Para[MAXPLAYERS + 1];
ArrayList g_arParachutes;
Cookie g_hCookie;
ConVar g_cvFallSpeed;
ConVar g_cvLinear;
ConVar g_cvDecrease;

char g_sClientModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];
float g_fFallSpeed;
float g_fDecrease;
bool g_bLate;
int g_iLinear;

public Plugin myinfo =
{
	name = "SM Parachute",
	author = "SWAT_88",
	description = "Adds a parachute with low gravity when you hold the use key",
	version = "2.7.0",
	url = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public OnPluginStart()
{
    g_cvFallSpeed = CreateConVar("sm_parachute_fallspeed", "100", "Speed of the fall when you use the parachute");
    g_cvLinear = CreateConVar("sm_parachute_linear", "1", "0: disables linear fallspeed - 1: enables it", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cvDecrease = CreateConVar("sm_parachute_decrease", "50", "0: dont use Realistic velocity-decrease - x: sets the velocity-decrease");

    g_cvFallSpeed.AddChangeHook(OnConVarChanged);
    g_cvLinear.AddChangeHook(OnConVarChanged);
    g_cvDecrease.AddChangeHook(OnConVarChanged);

    g_fFallSpeed = g_cvFallSpeed.FloatValue * -1.0;
    g_iLinear = g_cvLinear.IntValue;
    g_fDecrease = g_cvDecrease.FloatValue;

    RegConsoleCmd("sm_parachute", Command_Parachute);
    RegConsoleCmd("sm_para", Command_Parachute);
    RegConsoleCmd("sm_pchute", Command_Parachute);

    HookEvent("player_death", Event_OnPlayerDeath);
    HookEvent("round_start", Event_OnRoundStart);
    HookEvent("round_end", Event_OnRoundEnd);
    HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);

    AutoExecConfig(true);

    g_arParachutes = new ArrayList(sizeof(ParachuteInfo));
    g_hCookie = new Cookie("parachute_cookie", "Parachute model cookie for client", CookieAccess_Private);

    if (!g_bLate)
		return;

    PrecacheModels();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !AreClientCookiesCached(i) || IsFakeClient(i))
            continue;

        OnClientCookiesCached(i);

        if (IsPlayerAlive(i))
            CreateParachute(i);
    }
}

void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
    if (convar == g_cvFallSpeed)
        g_fFallSpeed = convar.FloatValue * -1.0;
    else if (convar == g_cvLinear)
        g_iLinear = convar.IntValue;
    else
        g_fDecrease = g_cvDecrease.FloatValue;
}

public void OnClientPutInServer(int client)
{
	g_Para[client].Reset();
}

public void OnClientDisconnect(int client)
{
	DeleteParachute(client);
}

public void OnClientCookiesCached(int client)
{
	if (!g_arParachutes.Length)
		return;

	char cookieValue[64];
	g_hCookie.Get(client, cookieValue, sizeof(cookieValue));

	if (cookieValue[0])
	{
		for (int i = 0; i < g_arParachutes.Length; i++)
		{
			ParachuteInfo info;
			g_arParachutes.GetArray(i, info, sizeof(info));
			if (strcmp(info.name, cookieValue) == 0)
			{
				FormatEx(g_sClientModel[client], sizeof(g_sClientModel[]), cookieValue);
				return;
			}
		}
	}

	ParachuteInfo info;
	g_arParachutes.GetArray(0, info, sizeof(info));
	FormatEx(g_sClientModel[client], sizeof(g_sClientModel[]), info.name);
}

public void OnMapStart()
{
	PrecacheModels();
	ReadDownloadsFile();
}

void PrecacheModels()
{
	g_arParachutes.Clear();

	char KvPath[128];
	BuildPath(Path_SM, KvPath, sizeof(KvPath), "configs/parachute_models.cfg");
	KeyValues Kv = new KeyValues("Models");
	if (!Kv.ImportFromFile(KvPath))
	{
		delete Kv;
		return;
	}

	if (!Kv.GotoFirstSubKey())
	{
		delete Kv;
		return;
	}

	do
	{
		ParachuteInfo info;
		Kv.GetSectionName(info.name, sizeof(ParachuteInfo::name));

		Kv.GetString("model", info.model, sizeof(ParachuteInfo::model));
		info.z = Kv.GetFloat("z");

		char angles[15];
		Kv.GetString("angles", angles, sizeof(angles), "0 0 0");

		char explodedAngles[3][16];
		if (ExplodeString(angles, " ", explodedAngles, 3, sizeof(explodedAngles[])) == 3)
		{
			info.angles[0] = StringToFloat(explodedAngles[0]);
			info.angles[1] = StringToFloat(explodedAngles[1]);
			info.angles[2] = StringToFloat(explodedAngles[2]);
		}
		else
			info.angles[0] = info.angles[1] = info.angles[2] = 0.0;

		PrecacheModel(info.model);

		g_arParachutes.PushArray(info, sizeof(info));
	} while(Kv.GotoNextKey());

	delete Kv;
}

void ReadDownloadsFile()
{
	char FilePath[128];
	BuildPath(Path_SM, FilePath, sizeof(FilePath), "configs/parachute_downloads.cfg");
	File DlFile = OpenFile(FilePath, "r");
	if (DlFile == null)
	{
		SetFailState("[Parachute] Could not find the downloads file, stopping the plugin...");
		return;
	}

	char Line[PLATFORM_MAX_PATH];
	while(!DlFile.EndOfFile() && DlFile.ReadLine(Line, sizeof(Line)))
	{
		TrimString(Line);
		AddFileToDownloadsTable(Line);
	}

	delete DlFile;
}

public void Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return;

	StopParachute(client);
}

public void Event_OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		CreateParachute(i);
	}
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		DeleteParachute(i);
	}
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !IsClientInGame(client) || IsFakeClient(client))
		return;

	CreateParachute(client);
}

public Action Command_Parachute(int client, int args)
{
	if (!client)
	{
		CReplyToCommand(client, "{green}[SM] {default}This command cannot be used from the server console.");
		return Plugin_Handled;
	}

	if (!AreClientCookiesCached(client))
	{
		CReplyToCommand(client, "{green}[SM] {default}Your settings (cookies) are not loaded yet. {olive}Please try this command again in a moment.");
		return Plugin_Handled;
	}

	OpenParachutesMenu(client);
	return Plugin_Handled;
}

void OpenParachutesMenu(int client)
{
	if (!g_arParachutes.Length)
		return;

	Menu menu = new Menu(ParachutesMenuHandler);
	menu.SetTitle("Choose your parachute model.\nSelected: %s", g_sClientModel[client]);

	for (int i = 0; i < g_arParachutes.Length; i++)
	{
		ParachuteInfo info;
		g_arParachutes.GetArray(i, info, sizeof(info));
		menu.AddItem(info.name, info.name, (strcmp(g_sClientModel[client], info.name) == 0) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.ExitButton = true;
	menu.Display(client, 32);
}

int ParachutesMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Select:
		{
			char model[64];
			menu.GetItem(param2, model, sizeof(model));
			FormatEx(g_sClientModel[param1], sizeof(g_sClientModel[]), model);
			g_hCookie.Set(param1, model);
			CPrintToChat(param1, "{green}[SM] {default}You have changed your {olive}Parachute model {lightgreen}to %s", model);
			OpenParachutesMenu(param1);
		}
	}

	return 0;
}

public void OnPlayerRunCmdPost(int client, int buttons)
{
	if (!(buttons & IN_USE) && !g_Para[client].active)
		return;

	if (!IsPlayerAlive(client))
		return;

	int flags = GetEntityFlags(client);

	// Stop parachute if conditions met
	if (g_Para[client].active)
	{
		if (!(buttons & IN_USE) || (flags & FL_ONGROUND) || (flags & FL_INWATER))
		{
			StopParachute(client);
			return;
		}

		if (GetEntityMoveType(client) == MOVETYPE_LADDER)
		{
			CreateTimer(0.5, Timer_StopParachute, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			StopParachute(client);
			return;
		}

		float velocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

		if (velocity[2] >= 0.0)
		{
			StopParachute(client);
			return;
		}

		UpdateParachute(client, velocity);
		TeleportParachute(client);
		return;
	}

	// Activate parachute if falling
	if ((flags & FL_ONGROUND) || (flags & FL_INWATER) || GetEntityMoveType(client) == MOVETYPE_LADDER)
		return;

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

	if (velocity[2] >= 0.0)
		return;

	g_Para[client].SetActive();
	UpdateParachute(client, velocity);
	DisplayParachute(client);
	TeleportParachute(client);
}

void UpdateParachute(int client, float velocity[3])
{
	float targetVelZ;

	if (velocity[2] >= g_fFallSpeed)
		g_Para[client].fallSpeed = true;

	if ((g_Para[client].fallSpeed && g_iLinear == 1) || g_fDecrease == 0.0)
		targetVelZ = g_fFallSpeed;
	else
		targetVelZ = velocity[2] + g_fDecrease;

	if (FloatAbs(velocity[2] - targetVelZ) > 0.5)
	{
		velocity[2] = targetVelZ;
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	}

	SetEntityGravity(client, 0.1);
}
bool GetClientParachuteInfo(int client, ParachuteInfo info)
{
	if (!g_arParachutes.Length)
		return false;

	for (int i = 0; i < g_arParachutes.Length; i++)
	{
		g_arParachutes.GetArray(i, info, sizeof(info));
		if (!g_sClientModel[client][0] || strcmp(info.name, g_sClientModel[client]) == 0)
			return true;
	}
	return false;
}

void CreateParachute(int client)
{
	DeleteParachute(client);

	ParachuteInfo info;
	if (!GetClientParachuteInfo(client, info))
		return;

	int ent = CreateEntityByName("prop_dynamic_override");
	if ((g_Para[client].entRef = EntIndexToEntRef(ent)) == INVALID_ENT_REFERENCE)
		return;

	g_Para[client].z = info.z;
	g_Para[client].angles = info.angles;

	DispatchKeyValue(ent, "model", info.model);
	DispatchKeyValue(ent, "fademindist", "-1");
	DispatchKeyValue(ent, "fademaxdist", "0");
	DispatchKeyValue(ent, "targetname", "parachute_prop");
	DispatchKeyValue(ent, "OnUser1", "!self,TurnOn,0,-1");
	DispatchKeyValue(ent, "OnUser2", "!self,TurnOff,0,-1");
	SetEntityMoveType(ent, MOVETYPE_NOCLIP);
	DispatchSpawn(ent);
}

void DeleteParachute(int client)
{
	int iParachuteEntity = g_Para[client].GetEntity();
	if (iParachuteEntity == -1)
	{
		g_Para[client].Reset();
		return;
	}

	// We always verify the entity we are going to remove
	char sModel[128];
	GetEntPropString(iParachuteEntity, Prop_Data, "m_ModelName", sModel, sizeof(sModel));

	// Something went wrong, we should not remove this entity
	if (strcmp(sModel, g_sClientModel[client], false) != 0)
	{
		char sClassName[64];
		GetEntityClassname(iParachuteEntity, sClassName, sizeof(sClassName));
		LogError("Blocked attempt to remove invalid entity %d (%s) for %L", iParachuteEntity, sClassName, client);
		return;
	}

	// All checks passed, we can remove the entity
	AcceptEntityInput(iParachuteEntity, "Kill");
	SetEntityGravity(client, 1.0);

	g_Para[client].Reset();
}

void DisplayParachute(int client)
{
	int iEnt = g_Para[client].GetEntity();
	if (iEnt == -1)
		return;

	AcceptEntityInput(iEnt, "FireUser1");
}

void HideParachute(int client)
{
	int iEnt = g_Para[client].GetEntity();
	if (iEnt == -1)
		return;

	AcceptEntityInput(iEnt, "FireUser2");
}

void TeleportParachute(int client)
{
	int iEnt = g_Para[client].GetEntity();
	if (iEnt == -1)
		return;

	float origin[3];
	float clientAngles[3];
	float parachuteAngles[3];

	GetClientAbsOrigin(client, origin);
	GetClientAbsAngles(client, clientAngles);

	origin[2] += g_Para[client].z;

	parachuteAngles[0] = g_Para[client].angles[0];
	parachuteAngles[1] = clientAngles[1] + g_Para[client].angles[1];
	parachuteAngles[2] = g_Para[client].angles[2];

	TeleportEntity(iEnt, origin, parachuteAngles, NULL_VECTOR);
}

void StopParachute(int client)
{
	SetEntityGravity(client, 1.0);
	g_Para[client].SetInactive();
	HideParachute(client);
}

public Action Timer_StopParachute(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
		return Plugin_Stop;

	StopParachute(client);
	return Plugin_Stop;
}
