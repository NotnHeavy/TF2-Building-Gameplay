// i'll try to be slightly less lazy with my programming here than i usually am with my gameknight plugins (the last one was awful lmao)
// still, probably no one will see this

// also if this plugin ever gets leaked:
// is this plugin jank? yes
// do i care? no
// i know is hould be using hull traces and stuff but meh lmao it's funnier

// also this uses smtc due to terrorist cutlvectors (well i didn't want to include it entirely so i made a nerfed Pointer include)

// 2024.08.18: ok i might actually upload this to github because it's a funny plugin considering how jank it is
// it doesn't crash servers at the very least i think so it's probably fine
// but anyway, actual real notice: i don't usually write code like this, i just get extremely lazy when i write
// plugins for solarlight's discord server. anyway, yes this code is horrible nasty jank and the plugin is full of
// bugs, i kept it like that though because i thought it was funny
//
// i have a bridge to sell you with this plugin

#define BG_FREEVIEW true

#pragma semicolon true 
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <dhooks>

#include <tf2attributes>

#include "Pointer"
#include "CUtlVector"

public Plugin myinfo =
{
    name = "NotnHeavy - Building Gameplay",
    author = "NotnHeavy",
    description = "Play as buildings rather than the traditional TF2 classes.",
    version = "1.0",
    url = "none"
};

// view angle update types for CPlayerState::fixangle
#define FIXANGLE_NONE			0
#define FIXANGLE_ABSOLUTE		1
#define FIXANGLE_RELATIVE		2

// m_lifeState values
#define	LIFE_ALIVE				0 // alive
#define	LIFE_DYING				1 // playing death animation or still falling off of a ledge waiting to hit ground
#define	LIFE_DEAD				2 // dead. lying still.
#define LIFE_RESPAWNABLE		3
#define LIFE_DISCARDBODY		4

enum
{
	OF_ALLOW_REPEAT_PLACEMENT				= 0x01,
	OF_MUST_BE_BUILT_ON_ATTACHMENT			= 0x02,
	OF_DOESNT_HAVE_A_MODEL					= 0x04,
	OF_PLAYER_DESTRUCTION					= 0x08,

	//
	// ADD NEW ITEMS HERE TO AVOID BREAKING DEMOS
	//

	OF_BIT_COUNT	= 4
};

// entity effects
enum
{
	EF_BONEMERGE			= 0x001,	// Performs bone merge on client side
	EF_BRIGHTLIGHT 			= 0x002,	// DLIGHT centered at entity origin
	EF_DIMLIGHT 			= 0x004,	// player flashlight
	EF_NOINTERP				= 0x008,	// don't interpolate the next frame
	EF_NOSHADOW				= 0x010,	// Don't cast no shadow
	EF_NODRAW				= 0x020,	// don't draw entity
	EF_NORECEIVESHADOW		= 0x040,	// Don't receive no shadow
	EF_BONEMERGE_FASTCULL	= 0x080,	// For use with EF_BONEMERGE. If this is set, then it places this ent's origin at its
										// parent and uses the parent's bbox + the max extents of the aiment.
										// Otherwise, it sets up the parent's bones every frame to figure out where to place
										// the aiment, which is inefficient because it'll setup the parent's bones even if
										// the parent is not in the PVS.
	EF_ITEM_BLINK			= 0x100,	// blink an item so that the user notices it.
	EF_PARENT_ANIMATES		= 0x200,	// always assume that the parent entity is animating
	EF_MAX_BITS = 10
};

enum
{
	MODE_TELEPORTER_ENTRANCE=0,
	MODE_TELEPORTER_EXIT,
};

enum 
{
	TTYPE_NONE=0,
	TTYPE_ENTRANCE,
	TTYPE_EXIT,
};

enum ObjectType_t
{
	OBJ_DISPENSER=0,
	OBJ_TELEPORTER,
	OBJ_SENTRYGUN,

	// Attachment Objects
	OBJ_ATTACHMENT_SAPPER,

	// If you add a new object, you need to add it to the g_ObjectInfos array 
	// in tf_shareddefs.cpp, and add it's data to the scripts/object.txt

	OBJ_LAST
};

enum Building_t
{
    BUILDING_DISPENSER,
    BUILDING_TELEPORTER,
    BUILDING_SENTRYGUN,
    BUILDING_SAPPER,
    BUILDING_MINI,
    BUILDING_SPYSENTRY,
    
    BUILDING_LAST
}

enum struct player_t
{
    Building_t m_eBuildingType;
    int m_hObject;
    bool m_bRelocateCamera;
    bool m_bInMenu;
    bool m_bNotSuicide;
    bool m_bDontDisableBroadcast;

    MoveType m_ePreviousMoveType;
    int m_hGroundEntity;
    int m_nPreviousButtons;
    float m_flHealthAdd;
    float m_flCameraOffset;
    float m_flFallVelocity;
    float m_vecLastOrigin[3];
    float m_vecAddVelocity[3];
    float m_vecNextOrigin[3];
    bool m_bNextOriginSet;
    bool m_bCrouching;
    float m_flTimeSinceSpawn;

    bool m_bDisguised;
    bool m_bAutoAiming;
    bool m_bUbercharging;
    bool m_bHealing[MAXPLAYERS + 1];
    float m_flUbercharge;
    float m_flTimeSinceDisguise;
    int m_hEntrance;

    bool BeingHealed()
    {
        for (int i = 0; i < sizeof(player_t::m_bHealing); ++i)
        {
            if (this.m_bHealing[i])
                return true;
        }
        return false;
    }
}
static player_t g_PlayerData[MAXPLAYERS + 1];

enum struct entity_t
{
    int m_hPlayer;
    bool m_bTeleporter;
}
static entity_t g_EntityData[2049];

enum struct map_t
{
    char m_szName[64];
    float m_vecSpawn[6]; // would be [3][2] but sourcepawn said NO. first 3 = red, last 3 = blu
    float m_flCamHeight;
}
static map_t g_MapData[] = {
    { "tr_walkway_fix", { 1.00, 2800.00, -350.00, 0.00, 0.00, 0.00 } },
    { "tr_walkway_rc2", { 1.00, 2800.00, -350.00, 0.00, 0.00, 0.00 } },

    { "plr_hightower", { 8080.00, 6470.00, 0.00, 6997.00, 8482.00, 150.00 } },

    { "koth_megaton", { 2131.00, -1903.02, 0.00, -2130.00, 1845.00, 0.00 } },
    { "koth_harvest_final", { -1000.00, -1976.00, 100.00, 1000.00, 2000.00, 100.00 }},
    { "koth_viaduct", { -1468.00, 2862.00, 160.00, -1451.00, -2744.00, 160.00 } },

    { "ctf_2fort_invasion", { 488.00, 1415.00, 360.00, -488.00, -1475.00, 360.00 } },

    { "pl_upward", { -701.00, -922.00, 670.00, -125.00, -1702.00, 350.00 } },
};

enum struct obj_t
{
    float m_flSpeed;
    int m_iMaxHealth;
    ObjectType_t m_eObjectType;
}
static obj_t g_ObjData[] = {
    { 300.00, 250, OBJ_DISPENSER },     // Dispenser
    { 250.00, 150, OBJ_TELEPORTER },    // Teleporter
    { 200.00, 325, OBJ_SENTRYGUN },     // Sentry Gun
    { 450.00, 50, OBJ_TELEPORTER },     // Sapper
    { 400.00, 100, OBJ_SENTRYGUN },     // Mini Sentry
    { 200.00, 125, OBJ_SENTRYGUN },     // Spy Sentry
};

static float g_vecOrigin[3] = { 50000.00, 50000.00, 0.00 }; // yes this will have map leaks, but whatever
static int explosionModelIndex;

static Handle sync;

static Handle SDKCall_CBaseEntity_ChangeTeam;
static Handle SDKCall_CBaseEntity_SetAbsOrigin;

static DynamicDetour DHooks_CObjectSentrygun_FindTarget;

static ConVar sv_gravity;

static any CTFPlayer_m_aObjects;
static any CBaseObject_m_flHealth;

static any MemoryPatch_CTFLaserPointer_Deploy;
static any MemoryPatch_CTFLaserPointer_Deploy_Old;
static any MemoryPatch_CTFLaserPointer_Deploy_New = 0.01;

static float lerp(float a, float b, float t)
{
    return (1 - t) * a + t * b;
}

static float fmin(float a, float b)
{
    return (a > b) ? b : a;
}

static int min(int a, int b)
{
    return (a > b) ? b : a;
}

static bool GetSpawnCoordinates(const char name[sizeof(map_t::m_szName)], TFTeam team, float buffer[3])
{
    for (int i = 0; i < sizeof(g_MapData); ++i)
    {
        if (strcmp(name, g_MapData[i].m_szName, false) == 0)
        {
            switch (team)
            {
                case TFTeam_Red:
                {
                    buffer[0] = g_MapData[i].m_vecSpawn[0];
                    buffer[1] = g_MapData[i].m_vecSpawn[1];
                    buffer[2] = g_MapData[i].m_vecSpawn[2];
                }
                case TFTeam_Blue:
                {
                    buffer[0] = g_MapData[i].m_vecSpawn[3];
                    buffer[1] = g_MapData[i].m_vecSpawn[4];
                    buffer[2] = g_MapData[i].m_vecSpawn[5];
                }
                default:
                    ThrowError("[Building Gameplay]: INCORRECT TEAM IN ::GetSpawnCoordinates()!");
            }
            return true;
        }
    }
    return false;
}

static void ObjectTypeToClassname(ObjectType_t m_eObjectType, char[] buffer, int maxlength)
{
    switch (m_eObjectType)
    {
        case OBJ_DISPENSER:
            strcopy(buffer, maxlength, "obj_dispenser");
        case OBJ_TELEPORTER:
            strcopy(buffer, maxlength, "obj_teleporter");
        case OBJ_SENTRYGUN:
            strcopy(buffer, maxlength, "obj_sentrygun");
        default:
            ThrowError("[Building Gameplay]: INCORRECT OBJECT TYPE IN ::ObjectTypeToClassname()!");
    }
}

static bool FloatEqual(float x, float y)
{
    if (FloatAbs(x - y) < 0.1)
        return true;
    return false;
}

public void OnPluginStart()
{
    PrintToServer("pootis spencer here");
    PrintToChatAll("pootis spencer here");

    GameData gamedata = new GameData("NotnHeavy - Building Gameplay");

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBaseEntity::ChangeTeam()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // int iTeamNum;
    SDKCall_CBaseEntity_ChangeTeam = EndPrepSDKCall();

    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CBaseEntity::SetAbsOrigin()");
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
    SDKCall_CBaseEntity_SetAbsOrigin = EndPrepSDKCall();

    DHooks_CObjectSentrygun_FindTarget = DynamicDetour.FromConf(gamedata, "CObjectSentrygun::FindTarget()");
    DHooks_CObjectSentrygun_FindTarget.Enable(Hook_Pre, CObjectSentrygun_FindTarget);

    CTFPlayer_m_aObjects = gamedata.GetOffset("CTFPlayer::m_aObjects");

    MemoryPatch_CTFLaserPointer_Deploy = view_as<any>(gamedata.GetMemSig("CTFLaserPointer::Deploy()")) + gamedata.GetOffset("MemoryPatch::CTFLaserPointer::Deploy()");
    MemoryPatch_CTFLaserPointer_Deploy_Old = LoadFromAddress(MemoryPatch_CTFLaserPointer_Deploy, NumberType_Int32);
    StoreToAddress(MemoryPatch_CTFLaserPointer_Deploy, AddressOf(MemoryPatch_CTFLaserPointer_Deploy_New), NumberType_Int32);

    delete gamedata;

    for (int i = MaxClients + 1; i < 2048; ++i)
    {
        if (IsValidEntity(i))
            OnEntityCreated(i, "");
    }

    HookEvent("player_spawn", player_spawn);
    HookEvent("player_death", player_death, EventHookMode_Pre);
    HookEvent("post_inventory_application", post_inventory_application);
    HookEvent("player_healed", player_healed);

    sv_gravity = FindConVar("sv_gravity");

    CBaseObject_m_flHealth = FindSendPropInfo("CBaseObject", "m_flPercentageConstructed") + 4;
    if (CBaseObject_m_flHealth != FindSendPropInfo("CBaseObject", "m_bHasSapper") - 4)
        ThrowError("*WARNING* M_FLHEALTH OFFSET IS WRONG!");

    sync = CreateHudSynchronizer();

    for (int i = 1; i <= MaxClients; ++i)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i);
            TF2_RespawnPlayer(i);
        }
    }
}

public void OnMapStart()
{
    explosionModelIndex = PrecacheModel("sprites/sprite_fire01.vmt");
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; ++i)
    {
        OnClientDisconnect(i);
    }

    // cleanup of props
    for (int i = MaxClients + 1; i < 2048; ++i)
    {
        if (IsValidEntity(i))
        {
            char buffer[64];
            GetEntityClassname(i, buffer, sizeof(buffer));
            if (StrContains(buffer, "obj_") == 0)
                RemoveEntity(i);
        }
    }

    StoreToAddress(MemoryPatch_CTFLaserPointer_Deploy, MemoryPatch_CTFLaserPointer_Deploy_Old, NumberType_Int32);
}

public void OnClientPutInServer(int client)
{
    g_PlayerData[client].m_eBuildingType = BUILDING_LAST;
    g_PlayerData[client].m_bRelocateCamera = true;
    g_PlayerData[client].m_bInMenu = false;
    SDKHook(client, SDKHook_GetMaxHealth, CTFPlayer_GetMaxHealth);
    SDKHook(client, SDKHook_OnTakeDamage, CTFPlayer_OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
    if (IsValidEntity(g_PlayerData[client].m_hObject) && g_PlayerData[client].m_hObject != 0)
        RemoveEntity(g_PlayerData[client].m_hObject);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!(0 <= entity < 2048))
        return;
    g_EntityData[entity].m_hPlayer = INVALID_ENT_REFERENCE;
    g_EntityData[entity].m_bTeleporter = false;
}

void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (g_PlayerData[client].m_eBuildingType != BUILDING_LAST)
        return;

    CreateObjectMenu(client);
    SetEntityRenderMode(client, RENDER_NONE);
}

Action player_death(Event event, const char[] name, bool dontBroadcast)
{
    int client = event.GetInt("victim_entindex");
    if (event.GetInt("customkill") == TF_CUSTOM_SUICIDE)
    {
        if (g_PlayerData[client].m_bNotSuicide)
            g_PlayerData[client].m_bNotSuicide = false;
        else
            return Plugin_Continue;
    }
    if (!g_PlayerData[client].m_bDontDisableBroadcast)
        event.BroadcastDisabled = true;
    return Plugin_Continue;
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (!IsValidEntity(viewmodel))
        return;
    SetEntProp(viewmodel, Prop_Send, "m_fEffects", EF_NODRAW);
}

void player_healed(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("patient"));
    g_PlayerData[client].m_flHealthAdd += float(event.GetInt("amount"));
}

int handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch (action)
    {
        case MenuAction_End:
        {
            delete menu;
        }
        case MenuAction_Select:
        {
            // CHECK IF TEAM IS VALID OTHERWISE SERVER WILL CRASH!
            TFTeam team = TF2_GetClientTeam(param1);
            if (team != TFTeam_Red && team != TFTeam_Blue)
                return 1;

            char buffer[64];
            menu.GetItem(param2, buffer, sizeof(buffer));

            int type = StringToInt(buffer);
            if (type < view_as<int>(BUILDING_LAST))
            {
                g_PlayerData[param1].m_eBuildingType = view_as<Building_t>(type);
                SpawnPlayer(param1);
            }
        }
    }
    return 0;
}

void CreateObjectMenu(int client)
{
    g_PlayerData[client].m_bRelocateCamera = true;
    g_PlayerData[client].m_eBuildingType = BUILDING_LAST;
    g_PlayerData[client].m_bInMenu = true;

    Menu menu = new Menu(handler);
    menu.OptionFlags = MENUFLAG_NO_SOUND;
    menu.SetTitle("Choose a building:");
    menu.AddItem("2", "Sentry Gun");
    menu.AddItem("0", "Dispenser");
    menu.AddItem("1", "Teleporter");
    menu.AddItem("4", "Mini Sentry");
    menu.AddItem("3", "Sapper");
    menu.AddItem("5", "Spy Sentry");
    menu.Display(client, MENU_TIME_FOREVER);
    SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void RemoveWeapons(int client)
{
    for (int i = 0; i <= 5; i++)
    {
        if (i == TFWeaponSlot_Secondary && g_PlayerData[client].m_bAutoAiming)
            continue;
        TF2_RemoveWeaponSlot(client, i);
    }

    // remove wearables (stolen from weapon manager i am too lazy to rewrite it)
    any m_hMyWearables = view_as<any>(GetEntityAddress(client)) + FindSendPropInfo("CTFPlayer", "m_hMyWearables");
    for (int index = 0, size = LoadFromAddress(m_hMyWearables + 0xC, NumberType_Int32); index < size; ++index)
    {
        // Get the wearable.
        int handle = LoadFromAddress(LoadFromAddress(m_hMyWearables, NumberType_Int32) + index * 4, NumberType_Int32);
        int wearable = EntRefToEntIndex(handle | (1 << 31));
        if (wearable == INVALID_ENT_REFERENCE)
            continue;

        TF2_RemoveWearable(client, wearable);
    }
}

int CreateBuilding(Building_t type, TFTeam team)
{
    char buffer[64];
    ObjectTypeToClassname(g_ObjData[type].m_eObjectType, buffer, sizeof(buffer));
    
    int obj = CreateEntityByName(buffer);
    DispatchSpawn(obj);

    switch (type)
    {
        case BUILDING_DISPENSER:
        {
            SetEntityModel(obj, "models/buildables/dispenser_lvl3.mdl");

            SetEntProp(obj, Prop_Send, "m_iAmmoMetal", 400);
            SetEntProp(obj, Prop_Send, "m_iState", 1);
            SetEntProp(obj, Prop_Send, "m_iUpgradeLevel", 3);
            SetEntProp(obj, Prop_Send, "m_iHighestUpgradeLevel", 3);
        }
        case BUILDING_SENTRYGUN:
        {
            SetEntityModel(obj, "models/buildables/sentry3.mdl");

            SetEntProp(obj, Prop_Send, "m_iAmmoShells", 144);
            
            SetEntProp(obj, Prop_Send, "m_iState", 1);
            SetEntProp(obj, Prop_Send, "m_iUpgradeLevel", 3);
            SetEntProp(obj, Prop_Send, "m_iAmmoRockets", 20);
            SetEntProp(obj, Prop_Send, "m_bPlayerControlled", false);
        }
        case BUILDING_TELEPORTER:
        {
            ActivateEntity(obj);
        }
        case BUILDING_SAPPER:
        {
            SetEntityModel(obj, "models/weapons/c_models/c_sapper/c_sapper.mdl");
            SetEntPropFloat(obj, Prop_Send, "m_flModelScale", 5.00);
        }
        case BUILDING_MINI:
        {
            SetEntityModel(obj, "models/buildables/sentry1.mdl");

            SetEntProp(obj, Prop_Send, "m_iAmmoShells", 144);
            SetEntProp(obj, Prop_Send, "m_iState", 1);
            SetEntProp(obj, Prop_Send, "m_iUpgradeLevel", 1);
            SetEntProp(obj, Prop_Send, "m_bPlayerControlled", false);
            SetEntProp(obj, Prop_Send, "m_bMiniBuilding", true);

            SetEntProp(obj, Prop_Send, "m_nSkin", view_as<int>(team));
        }
        case BUILDING_SPYSENTRY:
        {
            SetEntityModel(obj, "models/buildables/sentry3.mdl");

            SetEntProp(obj, Prop_Send, "m_iAmmoShells", 144);
            
            SetEntProp(obj, Prop_Send, "m_iState", 1);
            SetEntProp(obj, Prop_Send, "m_iUpgradeLevel", 3);
            SetEntProp(obj, Prop_Send, "m_iAmmoRockets", 20);
            SetEntProp(obj, Prop_Send, "m_bPlayerControlled", false);

            SetEntProp(obj, Prop_Send, "m_nSkin", view_as<int>(((team == TFTeam_Blue) ? TFTeam_Red : TFTeam_Blue)) - 2);
        }
    }
    
    if (type != BUILDING_MINI && type != BUILDING_SPYSENTRY)
        SetEntProp(obj, Prop_Send, "m_nSkin", view_as<int>(team) - 2);
    SetEntProp(obj, Prop_Send, "m_iObjectType", g_ObjData[type].m_eObjectType);
    SetEntProp(obj, Prop_Send, "m_iTeamNum", team);
    SetEntPropFloat(obj, Prop_Send, "m_flPercentageConstructed", 1.00);
    SetEntProp(obj, Prop_Send, "m_bHasSapper", 0);
    SetEntProp(obj, Prop_Send, "m_bPlacing", false);

    SetVariantInt(view_as<int>(team));
    AcceptEntityInput(obj, "TeamNum");
    SetVariantInt(view_as<int>(team));
    AcceptEntityInput(obj, "SetTeam");

    SetEntDataFloat(obj, CBaseObject_m_flHealth, float(g_ObjData[view_as<int>(type)].m_iMaxHealth));

    return EntIndexToEntRef(obj);
}

void HackBuilding(int client, int obj, TFTeam team)
{
    CUtlVector m_aObjects = view_as<CUtlVector>(Pointer(GetEntityAddress(client)) + view_as<Pointer>(CTFPlayer_m_aObjects));
    (m_aObjects.AddToTailGetPtr()).Write(obj & ~(1 << 31));

    // ABSOLUTE FUCKING HACK!
    // register in CTFTeam so that sentries can actually detect this
    SetEntProp(obj, Prop_Send, "m_iTeamNum", 0);
    SDKCall(SDKCall_CBaseEntity_ChangeTeam, obj, team);
}

void SpawnPlayer(int client)
{
    TFTeam team = TF2_GetClientTeam(client);
    int obj = CreateBuilding(g_PlayerData[client].m_eBuildingType, team);
    g_EntityData[EntRefToEntIndex(obj)].m_hPlayer = EntIndexToEntRef(client);
    SetEntPropEnt(obj, Prop_Send, "m_hBuilder", client);

    float buffer[3];
    char mapname[sizeof(map_t::m_szName)];
    GetCurrentMap(mapname, sizeof(mapname));
    if (!GetSpawnCoordinates(mapname, team, buffer))
        ThrowError("[Building Gameplay]: MAP %s IS NOT SUPPORTED!", mapname);
    TeleportEntity(obj, buffer);

    TF2_SetPlayerClass(client, TFClass_Heavy);
    TF2_RespawnPlayer(client);
    TF2_AddCondition(client, TFCond_DisguisedAsDispenser); // prevents them fron being spotted by sentry
    g_PlayerData[client].m_hObject = obj;
    g_PlayerData[client].m_flFallVelocity = 0.00;
    g_PlayerData[client].m_vecAddVelocity = { 0.00, 0.00, 0.00 }; // can't do { 0.00, ... }? maybe in the latest sourcepawn you can, not with what i'm compiling with for sure though
    g_PlayerData[client].m_flCameraOffset = 600.00;
    g_PlayerData[client].m_bAutoAiming = false;
    g_PlayerData[client].m_bDontDisableBroadcast = false;
    g_PlayerData[client].m_bUbercharging = false;
    g_PlayerData[client].m_flUbercharge = 0.00;
    g_PlayerData[client].m_hEntrance = INVALID_ENT_REFERENCE;
    g_PlayerData[client].m_bNextOriginSet = false;
    g_PlayerData[client].m_flHealthAdd = 0.00;
    g_PlayerData[client].m_flTimeSinceDisguise = 0.00;
    g_PlayerData[client].m_flTimeSinceSpawn = GetGameTime();
    for (int i = 1; i <= MaxClients; ++i)
        g_PlayerData[client].m_bHealing[i] = false;

    HackBuilding(client, obj, team);

    SDKHook(obj, SDKHook_OnTakeDamage, CBaseObject_OnTakeDamage);

#if defined BG_FREEVIEW
    SetVariantInt(1);
    AcceptEntityInput(client, "SetForcedTauntCam");
#endif

    if (g_PlayerData[client].m_eBuildingType == BUILDING_SPYSENTRY)
        g_PlayerData[client].m_bDisguised = true;
    else
        g_PlayerData[client].m_bDisguised = false;
}

bool TR_IgnoreSelfCamera(int entity, int contentsMask, any data)
{
    if (1 <= entity <= MaxClients)
        return false;
    if (IsValidEntity(g_EntityData[entity].m_hPlayer) && (1 <= EntRefToEntIndex(g_EntityData[entity].m_hPlayer) <= MaxClients))
        return false;
    if (data == entity || entity == EntRefToEntIndex(g_PlayerData[data].m_hObject))
        return false;
    return true;
}

bool TR_IgnoreSelf(int entity, int contentsMask, any data)
{
    if (1 <= entity <= MaxClients)
        return false;
    if (data == entity || entity == EntRefToEntIndex(g_PlayerData[data].m_hObject))
        return false;
    return true;
}

public void OnGameFrame()
{
    static int frame = 0;
    ++frame;
    for (int client = 1; client <= MaxClients; ++client)
    {
        if (!IsClientInGame(client))
            continue;
        RemoveWeapons(client);

        if (g_PlayerData[client].m_eBuildingType == BUILDING_LAST)
        {
            if (g_PlayerData[client].m_bRelocateCamera)
            {
                // this is a very ridiculous hack to force the player to basically "not see anything"
                // set their movetype to noclip and teleport them far far away, then set their velocity to
                // something decently high and now they're in the middle of fuck knows where :D
                float origin[3];
                origin = g_vecOrigin;
                SetEntPropVector(client, Prop_Data, "m_vecAbsOrigin", origin);
                TeleportEntity(client, .velocity = { 1000.00, 0.00, 0.00 });
            }
            else if (!g_PlayerData[client].m_bInMenu && IsPlayerAlive(client))
                CreateObjectMenu(client);
        }
        else if (IsValidEntity(g_PlayerData[client].m_hObject) && g_PlayerData[client].m_hObject != 0)
        {
            // get origin
            float origin[3];
            float og_origin[3];
            float angle[3];
            float new_origin[3];
            float vecMins[3];
            float vecMaxs[3];
            g_PlayerData[client].m_bInMenu = false;
            if (g_PlayerData[client].m_bNextOriginSet)
            {
                origin = g_PlayerData[client].m_vecNextOrigin;
                g_PlayerData[client].m_bNextOriginSet = false;
                TE_SetupExplosion(g_PlayerData[client].m_vecNextOrigin, explosionModelIndex, 10.0, 1, 0, 200, 0);
                TE_SendToAll();
            }
            else
                GetEntPropVector(g_PlayerData[client].m_hObject, Prop_Data, "m_vecAbsOrigin", origin);
            GetEntPropVector(g_PlayerData[client].m_hObject, Prop_Send, "m_vecMins", vecMins);
            GetEntPropVector(g_PlayerData[client].m_hObject, Prop_Send, "m_vecMaxs", vecMaxs);
            angle[1] = GetEntPropFloat(client, Prop_Send, "m_angEyeAngles[1]");
            new_origin = origin;
            og_origin = origin;

            // stop healing others at first
            for (int other = 1; other <= MaxClients; ++other)
                g_PlayerData[other].m_bHealing[client] = false;

            // make viewmodel invisible
            int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
            if (IsValidEntity(viewmodel))
                SetEntProp(viewmodel, Prop_Send, "m_fEffects", EF_NODRAW);

            // handle death
            if (!IsPlayerAlive(client))
            {
                RemoveEntity(g_PlayerData[client].m_hObject);
                TeleportEntity(client, g_PlayerData[client].m_vecLastOrigin);
                continue;
            }
            g_PlayerData[client].m_bDontDisableBroadcast = false;

            // set health of client to match building
            float m_flHealth = GetEntDataFloat(g_PlayerData[client].m_hObject, CBaseObject_m_flHealth);
            float m_flCanAdd = fmin(float(g_ObjData[g_PlayerData[client].m_eBuildingType].m_iMaxHealth) - m_flHealth, g_PlayerData[client].m_flHealthAdd);
            if (m_flCanAdd < 0.00)
                m_flCanAdd = 0.00;
            m_flHealth += m_flCanAdd;
            g_PlayerData[client].m_flHealthAdd = 0.00;
            if (m_flHealth > g_ObjData[g_PlayerData[client].m_eBuildingType].m_iMaxHealth && !g_PlayerData[client].BeingHealed())
                m_flHealth -= (float(g_ObjData[g_PlayerData[client].m_eBuildingType].m_iMaxHealth) / 30.00) * GetTickInterval();
            SetEntProp(client, Prop_Send, "m_iHealth", RoundFloat(m_flHealth));

            // show stats
            if (g_PlayerData[client].BeingHealed())
                SetHudTextParams(-1.0, 0.875, 0.5, 0, 255, 0, 0, 0, 6.0, 0.0, 0.0);
            else
                SetHudTextParams(-1.0, 0.875, 0.5, 255, 255, 255, 0, 0, 6.0, 0.0, 0.0);
            switch (g_PlayerData[client].m_eBuildingType)
            {
                case BUILDING_SENTRYGUN:
                {
                    int ammo = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", 144);
                    int rockets = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoRockets", 20);
                   
                    ShowSyncHudText(client, sync, "Ammo: %i Rockets: %i", ammo, rockets);
                }
                case BUILDING_DISPENSER:
                {
                    ShowSyncHudText(client, sync, "Ubercharge: %d%", RoundToFloor(g_PlayerData[client].m_flUbercharge));
                }
                case BUILDING_TELEPORTER:
                {
                    ShowSyncHudText(client, sync, "Entrance placed: %s", (IsValidEntity(g_PlayerData[client].m_hEntrance) ? "yes" : "no"));
                }
                case BUILDING_MINI:
                {
                    int ammo = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", 144);
                    ShowSyncHudText(client, sync, "Ammo: %i", ammo);
                }
                case BUILDING_SPYSENTRY:
                {
                    if (g_PlayerData[client].m_bDisguised)
                        ShowSyncHudText(client, sync, "Currently disguised");
                    else
                    {
                        int ammo = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", 144);
                        int rockets = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoRockets", 20);
                    
                        ShowSyncHudText(client, sync, "Ammo: %i Rockets: %i", ammo, rockets);
                    }
                }
            }

            // handle healing other players if dispenser
            if (g_PlayerData[client].m_eBuildingType == BUILDING_DISPENSER)
            {
                bool healing = false;
                for (int other = 1; other <= MaxClients; ++other)
                {
                    if ((g_PlayerData[client].m_bUbercharging || other != client) && IsClientInGame(other) && IsValidEntity(g_PlayerData[other].m_hObject) && g_PlayerData[other].m_hObject != 0 && TF2_GetClientTeam(client) == TF2_GetClientTeam(other))
                    {
                        float otherorigin[3];
                        float distance[3];
                        GetEntPropVector(g_PlayerData[other].m_hObject, Prop_Data, "m_vecAbsOrigin", otherorigin);
                        SubtractVectors(origin, otherorigin, distance);
                        g_PlayerData[other].m_bHealing[client] = (GetVectorLength(distance) < 250.00);
                        if (g_PlayerData[other].m_bHealing[client])
                            healing = true;
                    }
                }

                if (healing && !g_PlayerData[client].m_bUbercharging)
                    g_PlayerData[client].m_flUbercharge = fmin(g_PlayerData[client].m_flUbercharge + 4.00 * GetTickInterval(), 100.00);

                if (g_PlayerData[client].m_bUbercharging)
                {
                    SetEntPropFloat(g_PlayerData[client].m_hObject, Prop_Send, "m_flModelScale", 2.00);
                    g_PlayerData[client].m_flUbercharge -= (100.00 / 12.00) * GetTickInterval();
                    if (g_PlayerData[client].m_flUbercharge < 0.00)
                    {
                        g_PlayerData[client].m_flUbercharge = 0.00;
                        g_PlayerData[client].m_bUbercharging = false;
                        SetEntPropFloat(g_PlayerData[client].m_hObject, Prop_Send, "m_flModelScale", 1.00);
                    }
                }
            }

            // heal self and give ammo
            if (g_PlayerData[client].BeingHealed())
            {
                // see if any of the healers is ubercharging
                bool ubering = false;
                for (int i = 1; i <= MaxClients; ++i)
                {
                    if (g_PlayerData[client].m_bHealing[i] && g_PlayerData[i].m_bUbercharging)
                    {
                        ubering = true;
                        break;
                    }
                }

                m_flHealth = fmin(m_flHealth + (ubering ? 200.00 : 20.00) * GetTickInterval(), float(g_ObjData[g_PlayerData[client].m_eBuildingType].m_iMaxHealth) * 1.50);
                switch (g_PlayerData[client].m_eBuildingType)
                {
                    case BUILDING_SENTRYGUN:
                    {
                        if (frame % 5 == 0)
                        {
                            int ammo = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", 144);
                            SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", min(ammo + 1, 144));
                        }
                        if (frame % 66 == 0)
                        {
                            int rockets = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoRockets", 20);
                            SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoRockets", min(rockets + 1, 20));
                        }
                    }
                    case BUILDING_MINI:
                    {
                        if (frame % 5 == 0)
                        {
                            int ammo = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", 144);
                            SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_iAmmoShells", min(ammo + 1, 144));
                        }
                    }
                }
            }

            // set health
            SetEntDataFloat(g_PlayerData[client].m_hObject, CBaseObject_m_flHealth, m_flHealth, true);

            // nullify all of below if we are noclipping
            if (GetEntityMoveType(client) == MOVETYPE_NOCLIP)
            {
                if (g_PlayerData[client].m_ePreviousMoveType == MOVETYPE_NONE)
                    TeleportEntity(client, new_origin);
                GetClientAbsOrigin(client, origin);
                GetClientEyeAngles(client, angle);
                TeleportEntity(g_PlayerData[client].m_hObject, origin, angle);
                g_PlayerData[client].m_ePreviousMoveType = MOVETYPE_NOCLIP;
                continue;
            }
            else if (g_PlayerData[client].m_ePreviousMoveType == MOVETYPE_NOCLIP)
            {
                GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_PlayerData[client].m_vecAddVelocity);
                g_PlayerData[client].m_flFallVelocity = g_PlayerData[client].m_vecAddVelocity[2];
            }
            else
                g_PlayerData[client].m_flFallVelocity += g_PlayerData[client].m_vecAddVelocity[2];
            g_PlayerData[client].m_vecAddVelocity[2] = 0.00;

            // change camera offset
            int m_nButtons = GetEntProp(client, Prop_Data, "m_nButtons");
            if ((m_nButtons & IN_ATTACK2) && !(g_PlayerData[client].m_nPreviousButtons & IN_ATTACK2) && !g_PlayerData[client].m_bAutoAiming)
                g_PlayerData[client].m_flCameraOffset = ((g_PlayerData[client].m_flCameraOffset == 600.00) ? 100.00 : 600.00);

            // special functions
            if ((m_nButtons & IN_ATTACK3) && !(g_PlayerData[client].m_nPreviousButtons & IN_ATTACK3))
            {
                switch (g_PlayerData[client].m_eBuildingType)
                {
                    // sentries: control
                    case BUILDING_SENTRYGUN, BUILDING_MINI:
                    {
                        g_PlayerData[client].m_bAutoAiming = !g_PlayerData[client].m_bAutoAiming;
                        if (g_PlayerData[client].m_bAutoAiming)
                        {
                            float angles[3];
                            GetClientEyeAngles(client, angles);
                            angles[0] = 0.00;
                            TeleportEntity(client, .angles = angles);

                            int weapon = CreateEntityByName("tf_weapon_laser_pointer");
                            SetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex", 140);
                            SetEntProp(weapon, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
                            SetEntProp(weapon, Prop_Send, "m_bInitialized", true);
                            SetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity", client);
                            SetEntProp(weapon, Prop_Send, "m_iTeamNum", GetEntProp(client, Prop_Send, "m_iTeamNum"));
                            SetEntProp(weapon, Prop_Send, "m_bValidatedAttachedEntity", true); // fuck you
                            DispatchSpawn(weapon);
                            
                            TF2Attrib_SetByName(weapon, "deploy time decreased", 0.01);

                            EquipPlayerWeapon(client, weapon);
                        }
                    }

                    // dispenser: ubercharge
                    case BUILDING_DISPENSER:
                    {
                        if (g_PlayerData[client].m_flUbercharge == 100.00 && !g_PlayerData[client].m_bUbercharging)
                            g_PlayerData[client].m_bUbercharging = true;
                    }

                    // teleporter: place an entrance which other players can take
                    case BUILDING_TELEPORTER:
                    {
                        if (IsValidEntity(g_PlayerData[client].m_hGroundEntity))
                        {
                            // destroy existing entrance
                            if (IsValidEntity(g_PlayerData[client].m_hEntrance))
                            {
                                float entrance_origin[3];
                                GetEntPropVector(g_PlayerData[client].m_hEntrance, Prop_Data, "m_vecAbsOrigin", entrance_origin);
                                RemoveEntity(g_PlayerData[client].m_hEntrance);
                                TE_SetupExplosion(entrance_origin, explosionModelIndex, 10.0, 1, 0, 200, 0);
                                TE_SendToAll();
                            }

                            // create new entrance
                            int entrance = CreateBuilding(BUILDING_TELEPORTER, TF2_GetClientTeam(client));
                            TeleportEntity(entrance, g_PlayerData[client].m_vecLastOrigin);
                            SetEntPropEnt(entrance, Prop_Send, "m_hBuilder", client);
                            SetEntProp(entrance, Prop_Data, "m_iTeleportType", TTYPE_ENTRANCE); // gives it a cool effect :o
                            SetEntProp(entrance, Prop_Send, "m_iObjectMode", MODE_TELEPORTER_ENTRANCE);
                            HackBuilding(client, entrance, TF2_GetClientTeam(client));
            
                            // set m_hEntrance
                            int index = EntRefToEntIndex(entrance);
                            g_EntityData[index].m_hPlayer = EntIndexToEntRef(client);
                            g_EntityData[index].m_bTeleporter = true;
                            g_PlayerData[client].m_hEntrance = entrance;
                        }
                    }

                    // spy sentry: undisguise and start attacking
                    case BUILDING_SPYSENTRY:
                    {
                        if (GetGameTime() - g_PlayerData[client].m_flTimeSinceDisguise > 5.00)
                        {
                            TFTeam team = TF2_GetClientTeam(client);
                            if (g_PlayerData[client].m_bDisguised)
                            {
                                g_PlayerData[client].m_bDisguised = false;
                                SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_nSkin", view_as<int>(team) - 2);
                            }
                            else
                            {
                                g_PlayerData[client].m_bDisguised = true;
                                SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_nSkin", view_as<int>(((team == TFTeam_Blue) ? TFTeam_Red : TFTeam_Blue)) - 2);
                            }
                            g_PlayerData[client].m_flTimeSinceDisguise = GetGameTime();
                        }
                    }
                }
            }

            // set object flags of spy sentry if disguised so that players don't shoot at it
            if (g_PlayerData[client].m_eBuildingType == BUILDING_SPYSENTRY)
            {
                int flags = GetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_fObjectFlags");
                if (g_PlayerData[client].m_bDisguised)
                    SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_fObjectFlags", flags | OF_DOESNT_HAVE_A_MODEL);
                else
                    SetEntProp(g_PlayerData[client].m_hObject, Prop_Send, "m_fObjectFlags", flags & ~OF_DOESNT_HAVE_A_MODEL);
            }

            // find out height for player origin
            float test_origin[3];
            float vertical = g_PlayerData[client].m_flCameraOffset - 30.00;
            test_origin = origin;
            test_origin[2] += vertical;
            origin[2] += 30.00;
            TR_TraceRayFilter(origin, test_origin, MASK_PLAYERSOLID, RayType_EndPoint, TR_IgnoreSelfCamera, client);
            origin[2] -= 30.00;
            if (TR_DidHit())
            {
                float hit[3];
                TR_GetEndPosition(hit);
                if (hit[2] < test_origin[2])
                    vertical = hit[2];
            }

            // fix crouch
            g_PlayerData[client].m_bCrouching = !!(m_nButtons & IN_DUCK);
            SetEntityFlags(client, GetEntityFlags(client) & ~FL_DUCKING);

            // force origin of player
            float player_origin[3];
            float zeros[3] = { 0.00, ... };
            GetClientAbsOrigin(client, player_origin);
            origin[0] = lerp(player_origin[0], origin[0], 0.15);
            origin[1] = lerp(player_origin[1], origin[1], 0.15);
#if defined BG_FREEVIEW
            {
                float forwardVec[3];
                GetAngleVectors(angle, forwardVec, NULL_VECTOR, NULL_VECTOR);
                ScaleVector(forwardVec, -10.00);
                AddVectors(origin, forwardVec, origin);
                origin[2] = lerp(player_origin[2], origin[2] + (g_PlayerData[client].m_bCrouching ? -20.00 : 20.00), 0.15);
            }
#else
            if (g_PlayerData[client].m_bAutoAiming)
            {
                float forwardVec[3];
                GetAngleVectors(angle, forwardVec, NULL_VECTOR, NULL_VECTOR);
                ScaleVector(forwardVec, -10.00);
                AddVectors(origin, forwardVec, origin);
                origin[2] = lerp(player_origin[2], origin[2] + (g_PlayerData[client].m_bCrouching ? -20.00 : 20.00), 0.15);
            }
            else
                origin[2] = lerp(player_origin[2], origin[2] + vertical, 0.15);
#endif
            SetEntityMoveType(client, MOVETYPE_NONE);
            //TeleportEntity(client, origin, .velocity = zeros);
            TeleportEntity(client, .velocity = zeros);
            SDKCall(SDKCall_CBaseEntity_SetAbsOrigin, client, origin);

            // set up player movement
            float speed = g_ObjData[g_PlayerData[client].m_eBuildingType].m_flSpeed;
            if (g_PlayerData[client].m_bAutoAiming)
                speed /= ((g_PlayerData[client].m_eBuildingType == BUILDING_MINI) ? 2.25 : 5.00);
            float forwardVec[3];
            float rightVec[3];
            GetAngleVectors(angle, forwardVec, rightVec, NULL_VECTOR);
            ScaleVector(forwardVec, speed * GetTickInterval());
            ScaleVector(rightVec, speed * GetTickInterval());
            if (!((m_nButtons & (IN_FORWARD | IN_BACK)) == (IN_FORWARD | IN_BACK)))
            {
                if (m_nButtons & IN_FORWARD)
                    AddVectors(new_origin, forwardVec, new_origin);
                else if (m_nButtons & IN_BACK)
                    SubtractVectors(new_origin, forwardVec, new_origin);

            }
            if (!((m_nButtons & (IN_MOVELEFT | IN_MOVERIGHT)) == (IN_MOVELEFT | IN_MOVERIGHT)))
            {
                if (m_nButtons & IN_MOVELEFT)
                    SubtractVectors(new_origin, rightVec, new_origin);
                else if (m_nButtons & IN_MOVERIGHT)
                    AddVectors(new_origin, rightVec, new_origin);
            }
            new_origin[0] += g_PlayerData[client].m_vecAddVelocity[0] * GetTickInterval();
            new_origin[1] += g_PlayerData[client].m_vecAddVelocity[1] * GetTickInterval();

            // do trace to check collision
            if (!FloatEqual(origin[0], new_origin[0]) || !FloatEqual(origin[1], new_origin[1]))
            {
                og_origin[2] += vecMins[2] + vecMaxs[2];
                new_origin[2] += vecMins[2] + vecMaxs[2];
                TR_TraceRayFilter(og_origin, new_origin, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TR_IgnoreSelf, client);
                if (TR_DidHit())
                {
                    // check if this was another player as sapper
                    int hit = TR_GetEntityIndex();
                    int other_client = EntRefToEntIndex(g_EntityData[hit].m_hPlayer);
                    if (1 <= other_client <= MaxClients && g_PlayerData[client].m_eBuildingType == BUILDING_SAPPER)
                    {
                        ForcePlayerSuicide(client);
                        SDKHooks_TakeDamage(hit, client, client, 1000.00, DMG_BULLET);
                    }

                    new_origin = og_origin;
                }
                new_origin[2] -= vecMins[2] + vecMaxs[2];
                og_origin[2] -= vecMins[2] + vecMaxs[2];
            }

            // handle gravity
            int hGroundEntity = INVALID_ENT_REFERENCE;
            float floor_check[3];
            float floor_origin[3];
            if (g_PlayerData[client].m_flFallVelocity > 0.00)
            {
                floor_origin = new_origin;
                floor_origin[2] += (vecMins[2] + vecMaxs[2]);
                floor_check = floor_origin;
                floor_check[2] += g_PlayerData[client].m_flFallVelocity * GetTickInterval();
                TR_TraceRayFilter(floor_origin, floor_check, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TR_IgnoreSelf, client);
                if (TR_DidHit())
                {
                    int hit = TR_GetEntityIndex();
                    int owner_hit = EntRefToEntIndex(g_EntityData[hit].m_hPlayer);
                    if (1 <= owner_hit <= MaxClients)
                    {
                        float hit_origin[3];
                        float hit_vecMins[3];
                        float hit_vecMaxs[3];
                        GetEntPropVector(hit, Prop_Data, "m_vecAbsOrigin", hit_origin);
                        GetEntPropVector(g_PlayerData[client].m_hObject, Prop_Send, "m_vecMins", hit_vecMins);
                        GetEntPropVector(g_PlayerData[client].m_hObject, Prop_Send, "m_vecMaxs", hit_vecMaxs);
                        g_PlayerData[owner_hit].m_flFallVelocity = g_PlayerData[client].m_flFallVelocity + FloatAbs(g_PlayerData[owner_hit].m_flFallVelocity);
                        hit_origin[2] += hit_vecMins[2] + hit_vecMaxs[2];
                        TeleportEntity(hit, hit_origin);
                        
                    }
                    g_PlayerData[client].m_flFallVelocity = -g_PlayerData[client].m_flFallVelocity;
                }
            }

            floor_origin = new_origin;
            floor_origin[2] += (vecMins[2] + vecMaxs[2]) * 0.5;
            floor_check = floor_origin;
            floor_check[2] -= (vecMins[2] + vecMaxs[2]);
            g_PlayerData[client].m_flFallVelocity -= sv_gravity.FloatValue * GetTickInterval();
            TR_TraceRayFilter(floor_origin, floor_check, MASK_PLAYERSOLID_BRUSHONLY, RayType_EndPoint, TR_IgnoreSelf, client);
            if (TR_DidHit())
            {
                float hit[3];
                TR_GetEndPosition(hit);
                hGroundEntity = TR_GetEntityIndex();

                // check if we're still inside, if so don't bother
                float temp_origin[3];
                temp_origin = new_origin;
                temp_origin[2] = hit[2] + (vecMins[2] + vecMaxs[2]) * 1.5;
                floor_origin = temp_origin;
                floor_origin[2] += (vecMins[2] + vecMaxs[2]) * 0.5;
                floor_check = floor_origin;
                floor_check[2] -= (vecMins[2] + vecMaxs[2]);
                TR_TraceRayFilter(floor_origin, floor_check, MASK_PLAYERSOLID, RayType_EndPoint, TR_IgnoreSelf, client);
                if (!TR_DidHit())
                {
                    // check if this is a player
                    int owner_hit = EntRefToEntIndex(g_EntityData[hGroundEntity].m_hPlayer);
                    if (1 <= owner_hit <= MaxClients && g_PlayerData[client].m_flFallVelocity < 0.00)
                    {
                        // check if they're not grounded
                        if (g_PlayerData[owner_hit].m_hGroundEntity == INVALID_ENT_REFERENCE)
                            g_PlayerData[owner_hit].m_flFallVelocity += g_PlayerData[client].m_flFallVelocity;

                        // stomp the player?
                        else if (g_PlayerData[client].m_flFallVelocity < 400.00)
                            SDKHooks_TakeDamage(hGroundEntity, client, client, 1000.00, TF_CUSTOM_BOOTS_STOMP);

                        // are we a sapper?
                        if (g_PlayerData[client].m_eBuildingType == BUILDING_SAPPER && TF2_GetClientTeam(owner_hit) != TF2_GetClientTeam(client))
                        {
                            TE_SetupExplosion(new_origin, explosionModelIndex, 10.0, 1, 0, 200, 0);
                            TE_SendToAll();
                            ForcePlayerSuicide(client);
                            SDKHooks_TakeDamage(hGroundEntity, client, client, 1000.00, DMG_BULLET);
                        }
                    }

                    // check if this is a teleporter
                    if (g_EntityData[hGroundEntity].m_bTeleporter)
                    {
                        int other_client = EntRefToEntIndex(g_EntityData[hGroundEntity].m_hPlayer); 
                        if (((TF2_GetClientTeam(client) == TF2_GetClientTeam(other_client)) 
                            || (g_PlayerData[other_client].m_bDisguised)) 
                            && other_client != client)
                        {
                            int obj = g_PlayerData[other_client].m_hObject;

                            float exit_origin[3];
                            float exit_vecMins[3];
                            float exit_vecMaxs[3];
                            GetEntPropVector(obj, Prop_Data, "m_vecAbsOrigin", exit_origin);
                            GetEntPropVector(obj, Prop_Data, "m_vecMins", exit_vecMins);
                            GetEntPropVector(obj, Prop_Data, "m_vecMaxs", exit_vecMaxs);
                            exit_origin[2] += (exit_vecMins[2] + exit_vecMaxs[2]);

                            g_PlayerData[client].m_vecNextOrigin = exit_origin;
                            g_PlayerData[client].m_bNextOriginSet = true;
                        }
                    }

                    // should we take fall damage?
                    if (g_PlayerData[client].m_flFallVelocity < -1000.00)
                    {
                        g_PlayerData[client].m_bDontDisableBroadcast = true;
                        ForcePlayerSuicide(client);
                    }
                    
                    if (g_PlayerData[client].m_eBuildingType == BUILDING_SAPPER)
                        hit[2] += (vecMins[2] + vecMaxs[2]) / 2.00;
                    new_origin[2] = hit[2];
                    g_PlayerData[client].m_flFallVelocity = 0.00;

                    // lerp out added velocity
                    g_PlayerData[client].m_vecAddVelocity[0] = lerp(g_PlayerData[client].m_vecAddVelocity[0], 0.00, 0.085);
                    g_PlayerData[client].m_vecAddVelocity[1] = lerp(g_PlayerData[client].m_vecAddVelocity[1], 0.00, 0.085);
                }
                else
                {
                    hGroundEntity = INVALID_ENT_REFERENCE;
                    g_PlayerData[client].m_flFallVelocity = 0.00;
                }
            }
            else
                new_origin[2] += g_PlayerData[client].m_flFallVelocity * GetTickInterval();

            // handle jumping
            if (IsValidEntity(hGroundEntity) && m_nButtons & IN_JUMP)
            {
                new_origin[2] += vecMins[2] + vecMaxs[2];
                g_PlayerData[client].m_flFallVelocity = 300.00;
                hGroundEntity = INVALID_ENT_REFERENCE;
            }

            // teleport object
            TeleportEntity(g_PlayerData[client].m_hObject, .angles = angle);
            SetEntPropVector(g_PlayerData[client].m_hObject, Prop_Data, "m_angAbsRotation", angle);
            SDKCall(SDKCall_CBaseEntity_SetAbsOrigin, g_PlayerData[client].m_hObject, new_origin);
            g_PlayerData[client].m_vecLastOrigin = new_origin;
            g_PlayerData[client].m_hGroundEntity = hGroundEntity;

            // force angle of player
            // i FUCKIng hate this but i don't know an alternative
            if (!(83.00 < GetEntPropFloat(client, Prop_Send, "m_angEyeAngles[0]") < 84.00) && !g_PlayerData[client].m_bAutoAiming)
            {
                float angles[3];
                GetClientEyeAngles(client, angles);
                angles[0] = 83.50;
                //TeleportEntity(client, .angles = angles);
            }

            g_PlayerData[client].m_ePreviousMoveType = MOVETYPE_NONE;
            g_PlayerData[client].m_nPreviousButtons = m_nButtons;
        }
        else if (g_PlayerData[client].m_eBuildingType != BUILDING_LAST)
        {
            float buffer[3] = { 0.00, ... };
            TeleportEntity(client, g_PlayerData[client].m_vecLastOrigin, .velocity = buffer);

            if (IsPlayerAlive(client))
            {
                g_PlayerData[client].m_bNotSuicide = true;
                ForcePlayerSuicide(client);
            }
            g_PlayerData[client].m_eBuildingType = BUILDING_LAST;
            g_PlayerData[client].m_bRelocateCamera = false;
            TE_SetupExplosion(g_PlayerData[client].m_vecLastOrigin, explosionModelIndex, 10.0, 1, 0, 200, 0);
            TE_SendToAll();

            // destroy entrance if active
            if (IsValidEntity(g_PlayerData[client].m_hEntrance))
            {
                float entrance_origin[3];
                GetEntPropVector(g_PlayerData[client].m_hEntrance, Prop_Data, "m_vecAbsOrigin", entrance_origin);
                RemoveEntity(g_PlayerData[client].m_hEntrance);
                TE_SetupExplosion(entrance_origin, explosionModelIndex, 10.0, 1, 0, 200, 0);
                TE_SendToAll();
            }
        }
    }
}

static Action CTFPlayer_GetMaxHealth(int client, int &maxhealth)
{
    if (g_PlayerData[client].m_eBuildingType != BUILDING_LAST)
    {
        maxhealth = g_ObjData[view_as<int>(g_PlayerData[client].m_eBuildingType)].m_iMaxHealth;
        return Plugin_Changed;
    }
    return Plugin_Continue;
}

static Action CBaseObject_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    Action returnValue = Plugin_Continue;
    int client = EntRefToEntIndex(g_EntityData[victim].m_hPlayer);
    if (!IsValidEntity(client))
        return Plugin_Continue;

    // SAPPERS CAN'T DIE FOR FIRST 5 SECONDS
    if (GetGameTime() - g_PlayerData[client].m_flTimeSinceSpawn < 5.00 && g_PlayerData[client].m_eBuildingType == BUILDING_SAPPER)
        return Plugin_Handled;

    float newForce[3];
    newForce = damageForce;
    ScaleVector(newForce, 0.2);
    if (g_PlayerData[client].m_bCrouching)
        ScaleVector(newForce, 2.0);
    if (attacker == client && (damagetype & DMG_BLAST))
    {
        ScaleVector(newForce, 0.75);
        newForce[2] *= 0.2;
    }
    AddVectors(g_PlayerData[client].m_vecAddVelocity, newForce, g_PlayerData[client].m_vecAddVelocity);

    // remove sentry wrangler resistance
    if (HasEntProp(victim, Prop_Send, "m_bPlayerControlled") && GetEntProp(victim, Prop_Send, "m_bPlayerControlled"))
    {
        returnValue = Plugin_Changed;
        damage /= 0.33;
    }

    // just handle blast damage ourselves
    if (damagetype & DMG_BLAST)
    {
        // self damage resistance
        if (attacker == client)
            damage /= 1.20;

        float m_flHealth = GetEntDataFloat(victim, CBaseObject_m_flHealth) - damage;
        SetEntDataFloat(victim, CBaseObject_m_flHealth, m_flHealth, true);
        g_PlayerData[client].m_bNotSuicide = true;
        g_PlayerData[client].m_bDontDisableBroadcast = true;

        if (m_flHealth < 0.00)
            ForcePlayerSuicide(client);

        return Plugin_Handled;
    }
    return returnValue;
}

static Action CTFPlayer_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (IsValidEntity(inflictor))
    {
        char buffer[64];
        GetEntityClassname(inflictor, buffer, sizeof(buffer));
        if (StrContains(buffer, "obj_") == 0)
            return Plugin_Handled;
    }
    return Plugin_Continue;
}

static MRESReturn CObjectSentrygun_FindTarget(int entity, DHookReturn returnValue)
{
    // supercede if the spy sentry is disguised
    int client = EntRefToEntIndex(g_EntityData[entity].m_hPlayer);
    if (!(1 <= client <= MaxClients))
        return MRES_Ignored;

    if (g_PlayerData[client].m_bDisguised)
    {
        returnValue.Value = false;
        return MRES_Supercede;
    }
    return MRES_Ignored;
}