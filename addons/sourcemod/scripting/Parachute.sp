/*******************************************************************************
    SM Parachute
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
	Dolly132
	.Rushaway

    HAVE FUN!!!
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

ArrayList g_arParachutes;

Cookie g_hCookie;

char g_sClientModel[MAXPLAYERS + 1][PLATFORM_MAX_PATH];

ConVar g_cvParachuteFallSpeed;
ConVar g_cvParachuteLinear;
ConVar g_cvParachuteDecrease;

int g_iParachuteEntity[MAXPLAYERS+1] = {-1, ...};

bool g_bFallSpeed[MAXPLAYERS +1] = {false, ...};
bool g_bInUse[MAXPLAYERS+1] = {false, ...};
bool g_bHasParachuteModel[MAXPLAYERS+1] = {false, ...};

/* ConVar cache values */
float g_fFallSpeed;
int g_iLinear;
float g_fDecrease;

public Plugin myinfo =
{
	name = "SM Parachute",
	author = "SWAT_88",
	description = "Adds a parachute with low gravity when you hold the use key",
	version = "2.6.0",
	url = "http://www.sourcemod.net/"
};

public OnPluginStart()
{
	g_cvParachuteFallSpeed = CreateConVar("sm_parachute_fallspeed", "100", "Speed of the fall when you use the parachute");
	g_cvParachuteLinear = CreateConVar("sm_parachute_linear", "1", "0: disables linear fallspeed - 1: enables it");
	g_cvParachuteDecrease = CreateConVar("sm_parachute_decrease", "50", "0: dont use Realistic velocity-decrease - x: sets the velocity-decrease");

	g_cvParachuteFallSpeed.AddChangeHook(OnConVarChanged);
	g_cvParachuteLinear.AddChangeHook(OnConVarChanged);
	g_cvParachuteDecrease.AddChangeHook(OnConVarChanged);

	g_fFallSpeed = g_cvParachuteFallSpeed.FloatValue * -1.0;
	g_iLinear = g_cvParachuteLinear.IntValue;
	g_fDecrease = g_cvParachuteDecrease.FloatValue;

	RegConsoleCmd("sm_parachute", Command_Parachute);
	RegConsoleCmd("sm_para", Command_Parachute);
	RegConsoleCmd("sm_pchute", Command_Parachute);

	HookEvent("player_death", PlayerDeath);
	HookEvent("round_end", RoundEnd);

	AutoExecConfig(true);

	g_arParachutes = new ArrayList(sizeof(ParachuteInfo));

	g_hCookie = new Cookie("parachute_cookie", "Parachute model cookie for client", CookieAccess_Private);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !AreClientCookiesCached(i))
			continue;

		OnClientCookiesCached(i);
	}
}

void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	if (convar == g_cvParachuteFallSpeed)
		g_fFallSpeed = convar.FloatValue * -1.0;
	else if (convar == g_cvParachuteLinear)
		g_iLinear = convar.IntValue;
	else
		g_fDecrease = g_cvParachuteDecrease.FloatValue;
}

public void OnClientCookiesCached(int client)
{
	if (!g_arParachutes || !g_arParachutes.Length)
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

	// Dont set cookie if no cookie was found. Use default parachute model instead.
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
		{
			info.angles[0] = 0.0;
			info.angles[1] = 0.0;
			info.angles[2] = 0.0;
		}

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

public void OnClientDisconnect(int client)
{
	DeleteParachute(client);
	g_bFallSpeed[client] = false;
	g_bInUse[client] = false;
	g_sClientModel[client][0] = '\0';
}

public void PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	StopParachute(client);
}

public void RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		
		StopParachute(i);
		DeleteParachute(i);
		g_bFallSpeed[i] = false;
		g_bInUse[i] = false;
		g_iParachuteEntity[i] = -1;
		g_bHasParachuteModel[i] = false;
	}
}

public Action Command_Parachute(int client, int args)
{
	if (!client)
		return Plugin_Handled;

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
	if (!g_arParachutes || !g_arParachutes.Length)
		return;

	Menu menu = new Menu(ParachuteMenu);
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

int ParachuteMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}

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
	if (IsFakeClient(client) || !IsPlayerAlive(client))
		return;

	if (buttons & IN_USE)
	{
		bool justOpened = false;
		if (!g_bInUse[client])
		{
			g_bInUse[client] = true;
			g_bFallSpeed[client] = false;
			justOpened = true;
		}

		StartParachute(client, justOpened);
		TeleportParachute(client);
	}
	else
	{
		if (g_bInUse[client])
		{
			g_bInUse[client] = false;
			StopParachute(client);
		}
	}

	CheckClientLocation(client);
}

void StartParachute(int client, bool open)
{
	float velocity[3];
	GetEntPropVector(client, Prop_Send, "m_vecVelocity", velocity);

	if (velocity[2] >= g_fFallSpeed)
		g_bFallSpeed[client] = true;

	if (velocity[2] < 0.0)
	{
		if ((g_bFallSpeed[client] && g_iLinear == 1) || g_fDecrease == 0.0)
			velocity[2] = g_fFallSpeed;
		else
			velocity[2] = velocity[2] + g_fDecrease;

		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
		SetEntPropVector(client, Prop_Send, "m_vecVelocity", velocity);
		SetEntityGravity(client, 0.1);
		if (open)
			OpenParachute(client);
	}
}

bool GetClientParachuteInfo(int client, ParachuteInfo info)
{
	if (!g_arParachutes || !g_arParachutes.Length)
		return false;

	for (int i = 0; i < g_arParachutes.Length; i++)
	{
		g_arParachutes.GetArray(i, info, sizeof(info));
		if (!g_sClientModel[client][0] || strcmp(info.name, g_sClientModel[client]) == 0)
			return true;
	}
	return false;
}

void OpenParachute(int client)
{
	if (g_bHasParachuteModel[client])
		return;

	ParachuteInfo info;
	if (!GetClientParachuteInfo(client, info))
		return;

	g_iParachuteEntity[client] = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(g_iParachuteEntity[client], "model", info.model);
	SetEntityMoveType(g_iParachuteEntity[client], MOVETYPE_NOCLIP);
	DispatchSpawn(g_iParachuteEntity[client]);
	g_bHasParachuteModel[client] = true;
	TeleportParachute(client);
}

void TeleportParachute(int client)
{
	if (!g_bHasParachuteModel[client] || !IsValidEntity(g_iParachuteEntity[client]))
		return;

	ParachuteInfo info;
	if (!GetClientParachuteInfo(client, info))
		return;

	float origin[3];
	float clientAngles[3];
	float parachuteAngles[3];
	GetClientAbsOrigin(client, origin);
	GetClientAbsAngles(client, clientAngles);
	origin[2] += info.z;
	parachuteAngles[0] = info.angles[0];
	parachuteAngles[1] = clientAngles[1] + info.angles[1];
	parachuteAngles[2] = info.angles[2];
	TeleportEntity(g_iParachuteEntity[client], origin, parachuteAngles, NULL_VECTOR);
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
	if (g_bHasParachuteModel[client] && IsValidEntity(g_iParachuteEntity[client]))
	{
		AcceptEntityInput(g_iParachuteEntity[client], "Kill");
		g_bHasParachuteModel[client] = false;
	}
}

void CheckClientLocation(int client)
{
	if (!g_bInUse[client] && !g_bHasParachuteModel[client])
		return;

	float velocity[3];
	GetEntPropVector(client, Prop_Send, "m_vecVelocity", velocity);
	if (velocity[2] >= 0.0 || (GetEntityFlags(client) & FL_ONGROUND))
		StopParachute(client);
}
