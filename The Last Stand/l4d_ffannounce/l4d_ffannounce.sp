#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks> // DMG_BUCKSHOT
#include <colors>

#define PLUGIN_VERSION "4.1"

public Plugin myinfo = 
{
	name = "[L4D & 2] Survivor FF Announce",
	author = "AiMee, Forgetest",
	description = "Friendly Fire Announcements",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins",
}

#define TRANSLATION_FILE "l4d_ffannounce.phrases"

#define L4D2Team_Spectator 1
#define L4D2Team_Survivor 2

ConVar AnnounceEnable;
bool g_bBuckShot[MAXPLAYERS+1];
int DamageCache[MAXPLAYERS+1][MAXPLAYERS+1];
Handle FFTimer[MAXPLAYERS+1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	switch (GetEngineVersion())
	{
		case Engine_Left4Dead, Engine_Left4Dead2:
		{
			return APLRes_Success;
		}
	}
	strcopy(error, err_max, "Plugin supports only L4D & L4D2!");
	return APLRes_SilentFailure;
}

void LoadPluginTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "translations/" ... TRANSLATION_FILE ... ".txt");
	if (!FileExists(sPath))
	{
		SetFailState("Missing translation file \"" ... TRANSLATION_FILE ... ".txt\"");
	}
	LoadTranslations(TRANSLATION_FILE);
}

public void OnPluginStart()
{
	LoadPluginTranslations();
	
	AnnounceEnable = CreateConVar("l4d_ff_announce_enable", "1", "Enable announcing friendly-fire.\n(0 = Disabled, 1 = Announce in private, 2 = 1 + Announce to spectators).", FCVAR_SPONLY, true, 0.0, true, 2.0);
	AnnounceEnable.AddChangeHook(OnConVarChanged);
	OnConVarChanged(AnnounceEnable, "", "");
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ToggleEvents(AnnounceEnable.BoolValue);
}

void ToggleEvents(bool hook)
{
	static bool hooked = false;
	if (hook && !hooked)
	{
		hooked = true;
		HookEvent("player_hurt_concise", Event_HurtConcise);
		HookEvent("player_bot_replace", Event_BotReplacePlayer);
		HookEvent("bot_player_replace", Event_PlayerReplaceBot);
	}
	else if (!hook && hooked)
	{
		hooked = false;
		UnhookEvent("player_hurt_concise", Event_HurtConcise);
		UnhookEvent("player_bot_replace", Event_BotReplacePlayer);
		UnhookEvent("bot_player_replace", Event_PlayerReplaceBot);
	}
}

void Event_BotReplacePlayer(Event event, const char[] name, bool dontBroadcast)
{
	HandlePlayerReplace(GetClientOfUserId(event.GetInt("bot")), GetClientOfUserId(event.GetInt("player")));
}

void Event_PlayerReplaceBot(Event event, const char[] name, bool dontBroadcast)
{
	HandlePlayerReplace(GetClientOfUserId(event.GetInt("player")), GetClientOfUserId(event.GetInt("bot")));
}

void HandlePlayerReplace(int replacer, int replacee)
{
	if (FFTimer[replacee] != null)
	{
		for (int i = 1; i <= MaxClients; ++i)
		{
			DamageCache[replacer][i] = DamageCache[replacee][i];
		}
		delete FFTimer[replacee];
		StartAnnounceTimer(replacer, 1.5);
	}
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (DamageCache[i][replacee])
		{
			DamageCache[i][replacer] = DamageCache[i][replacee];
			DamageCache[i][replacee] = 0;
		}
	}
}

public void OnClientDisconnect(int client)
{
	g_bBuckShot[client] = false;
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; ++i)
	{
		FFTimer[i] = null;
	}
}

void OnNextFrame_Unmark(int userid)
{
	g_bBuckShot[GetClientOfUserId(userid)] = false;
}

void Event_HurtConcise(Event event, const char[] name, bool dontBroadcast)
{
	int attacker	= event.GetInt("attackerentid");
	int victim		= GetClientOfUserId(event.GetInt("userid"));
	
	if (!attacker || !victim) return;
	if (GetClientTeam(attacker) != L4D2Team_Survivor || IsFakeClient(attacker)) return;
	if (GetClientTeam(victim)	!= L4D2Team_Survivor) return;
	
	if (attacker == victim) return;
	
	// Shotgun deals damage per pellet, which means the event can be called multiple times for one shot.
	// Prevent unnecessary freeing timers that might impact performance.
	if (event.GetInt("type") & DMG_BUCKSHOT && !g_bBuckShot[attacker])
	{
		RequestFrame(OnNextFrame_Unmark, GetClientUserId(attacker));
		g_bBuckShot[attacker] = true;
	}
	
	int damage = event.GetInt("dmg_health");
	if (FFTimer[attacker] != null)
	{
		DamageCache[attacker][victim] += damage;
		DamageCache[attacker][0] += damage;
		
		if (!g_bBuckShot[attacker])
		{
			delete FFTimer[attacker];
			StartAnnounceTimer(attacker, 1.5);
		}
	}
	else 
	{
		for (int i = 1; i <= MaxClients; ++i) DamageCache[attacker][i] = 0;
		
		DamageCache[attacker][victim] = damage;
		DamageCache[attacker][0] = damage;
		StartAnnounceTimer(attacker, 1.5);
	}
}

void StartAnnounceTimer(int client, float interval)
{
	DataPack dp;
	FFTimer[client] = CreateDataTimer(interval, AnnounceFF, dp, TIMER_FLAG_NO_MAPCHANGE);
	dp.WriteCell(client);
	dp.WriteCell(GetClientUserId(client));
}

Action AnnounceFF(Handle timer, DataPack dp) 
{
	dp.Reset();
	
	int attacker = dp.ReadCell();
	int attackerid = dp.ReadCell();
	
	FFTimer[attacker] = null;
	
	if (attacker != GetClientOfUserId(attackerid) || !IsClientInGame(attacker))
		return Plugin_Stop;
	
	int total = 0;
	int[] clients = new int[MaxClients];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (!DamageCache[attacker][i]) continue;
		
		clients[total++] = i;
		
		if (!IsFakeClient(i))
		{
			CPrintToChat(i, "%t", "FFAnnounceToVictim", i, DamageCache[attacker][i]);
		}
	}
	
	if (total > 0)
	{
		static char text[400], msg[400];
		
		static char transStr[64];
		FormatEx(transStr, sizeof(transStr), "FFAnnounceToGuilty%i", total);
		FormatEx(text, sizeof(text), "%T", transStr, attacker);
		
		static char buffer[64];
		for (int i = 0; i < total; ++i)
		{
			FormatEx(transStr, sizeof(transStr), "{VICTIM%i_NAME}", i+1);
			GetClientName(clients[i], buffer, sizeof(buffer));
			ReplaceString(text, sizeof(text), transStr, buffer);
			FormatEx(transStr, sizeof(transStr), "{VICTIM%i_DMG}", i+1);
			IntToString(DamageCache[attacker][clients[i]], buffer, sizeof(buffer));
			ReplaceString(text, sizeof(text), transStr, buffer);
		}
		
		strcopy(msg, sizeof(msg), text);
		FormatEx(buffer, sizeof(buffer), "%T", "You", attacker);
		ReplaceString(msg, sizeof(msg), "{GUILTY}", buffer);
		
		CPrintToChat(attacker, msg);
		CPrintToChat(attacker, "%t", "FFAnnounceToGuiltyTotal", DamageCache[attacker][0]);
		
		if (AnnounceEnable.IntValue > 1)
		{
			GetClientName(attacker, buffer, sizeof(buffer));
			ReplaceString(text, sizeof(text), "{GUILTY}", buffer);
			CPrintToSpectators(text);
		}
	}
	
	return Plugin_Stop;
}

void CPrintToSpectators(const char[] msg)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == L4D2Team_Spectator)
		{
			CPrintToChat(i, msg);
		}
	}
}
