#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo =
{
	name = "[L4D & 2] Death Item Glow",
	author = "Forgetest",
	description = "Add a glow to items dropped by dead survivors.",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
};

enum struct WeaponGlowInfo
{
	int key;
	int glowRef;
}

ArrayList g_WeaponGlowList;
int g_GlowColor[3];
float g_flGlowTIme;

public void OnPluginStart()
{
	CreateConVarHook("l4d_death_item_glow_color",
					"255 255 255",
					"Glow color (RGB) for items drooped by dead survivors.",
					FCVAR_NONE,
					false, 0.0, false, 0.0,
					CvarChg_GlowColor);
	
	CreateConVarHook("l4d_death_item_glow_time",
					"-1",
					"Glow time for items drooped by dead survivors.\n"
				...	"Value: -1 = Forever, 0.0 = Glow disabled, others = Glow time.",
					FCVAR_NONE,
					true, -1.0, false, 0.0,
					CvarChg_GlowTime);
	
	g_WeaponGlowList = new ArrayList(sizeof(WeaponGlowInfo));
	
	HookEvent("round_start", Event_RoundStart);
	
	for (int i = 1; i <= MaxClients; ++i)
	{
		if (IsClientInGame(i)) OnClientPutInServer(i);
	}
}

void CvarChg_GlowColor(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int color[3];
	char sColor[12];
	convar.GetString(sColor, sizeof(sColor));
	if (StringToColor(sColor, color))
		g_GlowColor = color;
}

void CvarChg_GlowTime(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_flGlowTIme = convar.FloatValue;
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_WeaponGlowList.Clear();
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponDropPost, SDK_OnWeaponDrop_Post);
	SDKHook(client, SDKHook_WeaponEquipPost, SDK_OnWeaponEquip_Post);
}

void SDK_OnWeaponDrop_Post(int client, int weapon)
{
	if (GetClientHealth(client) > 0)
		return;

	AddWeaponGlow(weapon);
	
	CheckGlowTime(weapon);
}

void SDK_OnWeaponEquip_Post(int client, int weapon)
{
	RemoveWeaponGlow(weapon);
}

void AddWeaponGlow(int weapon)
{
	int glow = -1;
	if (L4D_IsEngineLeft4Dead())
		glow = CreateGlowEntity(weapon);
	else
		L4D2_SetEntityGlow(weapon, L4D2Glow_Constant, 0, 0, g_GlowColor, false);
	
	int key = EntIndexToEntRef(weapon);
	g_WeaponGlowList.Set(g_WeaponGlowList.Push(key), EntIndexToEntRef(glow), WeaponGlowInfo::glowRef);
}

void RemoveWeaponGlow(int weapon)
{
	int key = EntIndexToEntRef(weapon);
	int index = g_WeaponGlowList.FindValue(key);
	if (index != -1)
	{
		L4D2_RemoveEntityGlow(weapon);
		
		if (L4D_IsEngineLeft4Dead())
		{
			int glow = EntRefToEntIndex(g_WeaponGlowList.Get(index, WeaponGlowInfo::glowRef));
			if (IsValidEdict(glow))
				RemoveEntity(glow);
		}
		
		g_WeaponGlowList.Erase(index);
	}
}

void CheckGlowTime(int weapon)
{
	if (g_flGlowTIme < 0.0)
		return;
	
	if (g_flGlowTIme == 0.0)
	{
		RemoveWeaponGlow(weapon);
	}
	else
	{
		CreateTimer(g_flGlowTIme, Timer_RemoveWeaponGlow, EntIndexToEntRef(weapon), TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_RemoveWeaponGlow(Handle timer, int entRef)
{
	int weapon = EntRefToEntIndex(entRef);
	if (IsValidEdict(weapon) && g_WeaponGlowList.FindValue(entRef) != -1)
	{
		RemoveWeaponGlow(weapon);
	}
	return Plugin_Stop;
}

// copied from "l4d2_tank_props_glow" by Harry Potter, thanks to this guy :)
int CreateGlowEntity(int entity)
{
	// Spawn dynamic prop entity
	int glow = CreateEntityByName("prop_dynamic_override");
	if (glow == -1) {
		return -1;
	}

	// Get position of hittable
	float origin[3];
	float angles[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", angles);

	// Get Client Model
	char sModelName[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));

	// Set new fake model
	SetEntityModel(glow, sModelName);
	DispatchSpawn(glow);

	// Set outline glow color
	SetEntProp(glow, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(glow, Prop_Send, "m_nSolidType", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRange", 0);
	SetEntProp(glow, Prop_Send, "m_nGlowRangeMin", 0);
	SetEntProp(glow, Prop_Send, "m_iGlowType", L4D2Glow_Constant);
	SetEntProp(glow, Prop_Send, "m_glowColorOverride", g_GlowColor[0] | g_GlowColor[1] << 8 | g_GlowColor[2] << 16);
	AcceptEntityInput(glow, "StartGlowing");

	// Set model invisible
	SetEntityRenderMode(glow, RENDER_NONE);
	SetEntityRenderColor(glow, 0, 0, 0, 0);

	// Set model to hittable position
	TeleportEntity(glow, origin, angles, NULL_VECTOR);

	// Set model attach to client, and always synchronize
	SetVariantString("!activator");
	AcceptEntityInput(glow, "SetParent", entity);
	
	return glow;
}

bool StringToColor(const char[] str, int color[3])
{
	char bits[3][4];
	if (ExplodeString(str, " ", bits, sizeof(bits), sizeof(bits[]), true) < sizeof(bits))
		return false;
	
	for (int i = 0; i < sizeof(bits); ++i)
	{
		if (!StringToIntEx(bits[i], color[i]))
			return false;
	}
	
	return true;
}

ConVar CreateConVarHook(const char[] name,
	const char[] defaultValue,
	const char[] description="",
	int flags=0,
	bool hasMin=false, float min=0.0,
	bool hasMax=false, float max=0.0,
	ConVarChanged callback)
{
	ConVar cv = CreateConVar(name, defaultValue, description, flags, hasMin, min, hasMax, max);
	
	Call_StartFunction(INVALID_HANDLE, callback);
	Call_PushCell(cv);
	Call_PushNullString();
	Call_PushNullString();
	Call_Finish();
	
	cv.AddChangeHook(callback);
	
	return cv;
}
