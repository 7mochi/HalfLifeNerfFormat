#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <fun>
#include <xs>

#define PLUGIN_NAME  			"Half-Life Nerf"
#define PLUGIN_VERSION 			"1.0.0"
#define PLUGIN_AUTHOR  			"szGabu"

#define NERF_GAMENAME			"HL Nerf Server"
#define HL25_CHECK				"sv_allow_autoaim"

#define V_DISTANCE 				9999.0
#define V_WALL 					1.0

#define LOOP_ESCAPE_THRESHOLD	100

#define MAX_HUD_MESSAGE_LENGTH  480

new bool:g_bNerfFormatEnabled = false;

new bool:g_bStopStreak = false;
new Float:g_fStreakThreshold = 1.5;
new Float:g_fStreakRollValue = 30.0;
new bool:g_bDisableWallGauss = false;
new Float:g_fGaussDmgMultiplier = 1.0;
new Float:g_fEgonDmgMultiplier = 1.0;
new Float:g_fCrossbowDmgMultiplier = 1.0;
new bool:g_bSpawnProtect = false;
new Float:g_fSpawnProtectTime = 1.0;
new g_iSpawnProtectShellThickness = 25;
new bool:g_bShowRuleSet = false;

new Float:g_fWallSteep[3];

enum {
    BANNED_ITEM_BATTERY,
    BANNED_ITEM_LONGJUMP,
    BANNED_ITEM_AR_GRENADES,
    BANNED_ITEM_CROSSBOW_AMMO,
    BANNED_ITEM_BUCKSHOT_AMMO,
    BANNED_ITEM_EGON,
};

new g_iPluginFlags;

new const g_szItems[][] = {
    "item_battery",
    "item_longjump",
    "ammo_ARgrenades",
    "ammo_crossbow",
    "ammo_buckshot",
    "weapon_egon"
};

new Float:g_fPlayerItemRoll[MAX_PLAYERS+1][sizeof g_szItems];
new bool:g_bPlayerShouldRollForItems[MAX_PLAYERS+1] = { false, ... };
new bool:g_bIsRolling[MAX_PLAYERS+1] = { false, ... };
new bool:g_bCanPlayEmptySound[MAX_PLAYERS+1] = { true, ... }
new bool:g_bShouldPreventBleeding[MAX_PLAYERS+1] = { false, ... };
new bool:g_bIsHL25 = false;
new bool:g_bCanThrowCrowbar = false;
new g_iSelfGaussType = -1;
new g_iSpawnType = -1;
new bool:g_bUncappedBunny = false;

#define STOP_STREAK_DEFAULT_VALUE					"1"
#define STOP_STREAK_KD_DEFAULT_VALUE				"1.5"
#define STOP_ITEM_PERCENTAGE_DEFAULT_VALUE			"30.0"
#define DISABLE_WALLGAUSS_DEFAULT_VALUE				"1"
#define GAUSS_DMG_MULTIPLIER_DEFAULT_VALUE			"0.75"
#define EGON_DMG_MULTIPLIER_DEFAULT_VALUE			"0.75"
#define CROSSBOW_DMG_MULTIPLIER_DEFAULT_VALUE		"0.825"
#define SPAWN_PROTECT_DEFAULT_VALUE					"1"
#define SPAWN_PROTECT_DEFAULT_TIME					"1"

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

	g_bIsHL25 = get_cvar_pointer(HL25_CHECK) != 0;

	bind_pcvar_num(create_cvar("amx_nerf_enabled", "1", FCVAR_NONE, "Determines if the Nerf format should be enabled, takes effect at map start.", true, 0.0, true, 1.0), g_bNerfFormatEnabled);
	bind_pcvar_num(create_cvar("amx_nerf_stop_streak", STOP_STREAK_DEFAULT_VALUE, FCVAR_NONE, "Determines if the leading player (by K/D, not score) should be additonally nerfed, items may dissapear forhim.", true, 0.0, true, 1.0), g_bStopStreak);
	bind_pcvar_float(create_cvar("amx_nerf_stop_streak_threshold", STOP_STREAK_KD_DEFAULT_VALUE, FCVAR_NONE, "By how much the Streak Threshold must be leading forplayers to be additionally nerfed.", true, 1.0, true, 3.0), g_fStreakThreshold);
	bind_pcvar_float(create_cvar("amx_nerf_stop_item_percentage", STOP_ITEM_PERCENTAGE_DEFAULT_VALUE, FCVAR_NONE, "The amount to roll forbanned items when an user is stomping, if above this value (0-100) then the item will be hidden from him.", true, 1.0, true, 100.0), g_fStreakRollValue);
	bind_pcvar_num(create_cvar("amx_nerf_disable_wallgauss", DISABLE_WALLGAUSS_DEFAULT_VALUE, FCVAR_NONE, "Determines if vanilla 'wall gauss' shots should be disabled. If enabled, only true wall gauss shots will be registered as such.", true, 0.0, true, 1.0), g_bDisableWallGauss);
	bind_pcvar_float(create_cvar("amx_nerf_nerfed_gauss_dmg_multiplier", GAUSS_DMG_MULTIPLIER_DEFAULT_VALUE, FCVAR_NONE, "Multiply the gauss damage by this value. Less value is less damage", true, 0.0, true, 1.0), g_fGaussDmgMultiplier);
	bind_pcvar_float(create_cvar("amx_nerf_nerfed_egon_dmg_multiplier", EGON_DMG_MULTIPLIER_DEFAULT_VALUE, FCVAR_NONE, "Multiply the egon damage by this value. Less value is less damage", true, 0.0, true, 1.0), g_fEgonDmgMultiplier);
	bind_pcvar_float(create_cvar("amx_nerf_nerfed_crossbow_dmg_multiplier", CROSSBOW_DMG_MULTIPLIER_DEFAULT_VALUE, FCVAR_NONE, "Multiply the crossbow damage by this value. Less value is less damage", true, 0.0, true, 1.0), g_fCrossbowDmgMultiplier);
	bind_pcvar_num(create_cvar("amx_nerf_spawn_protect", SPAWN_PROTECT_DEFAULT_VALUE, FCVAR_NONE, "Determines if spawning players should be protected against instant damage.", true, 0.0, true, 1.0), g_bSpawnProtect);
	bind_pcvar_float(create_cvar("amx_nerf_spawn_protect_time", SPAWN_PROTECT_DEFAULT_TIME, FCVAR_NONE, "Determines the time of spawn protection.", true, 0.0, true, 10.0), g_fSpawnProtectTime);
	bind_pcvar_num(create_cvar("amx_nerf_spawn_protect_shell_thickness", "25", FCVAR_NONE, "Determines the visual shell around players if they're spawn protected.", true, 0.0, true, 255.0), g_iSpawnProtectShellThickness);
	bind_pcvar_num(create_cvar("amx_nerf_spawn_show_ruleset", "1", FCVAR_NONE, "Display the nerf ruleset when a player joins the server.", true, 0.0, true, 1.0), g_bShowRuleSet);

	g_iPluginFlags = plugin_flags();

	AutoExecConfig();
}

public plugin_cfg()
{
	if(g_bNerfFormatEnabled)
	{
		register_dictionary("hl_nerf_gamerules.txt");

		RegisterHam(Ham_TakeDamage, "player", "HamForward_PlayerTakeDamage_Pre");
		RegisterHam(Ham_Spawn, "player", "HamForward_PlayerSpawn_Post", true);
		RegisterHam(Ham_BloodColor, "player", "HamForward_PlayerBloodColor_Pre");
		RegisterHam(Ham_Weapon_WeaponIdle, "weapon_gauss", "HamForward_GaussWeaponIdle_Pre");
		RegisterHam(Ham_Weapon_WeaponIdle, "weapon_gauss", "HamForward_GaussWeaponIdle_Post", true);
		RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_gauss", "HamForward_GaussWeaponIdle_Pre"); //we reuse the same function forthe primary attack because it's literally the same logic
		RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_gauss", "HamForward_GaussWeaponIdle_Post", true); //ditto
		RegisterHam(Ham_Use, "func_recharge", "HamForward_RechargerUse_Pre");

		register_forward(FM_AddToFullPack, "MetaForward_AddToFullPack_Pre");
		register_forward(FM_AddToFullPack, "MetaForward_AddToFullPack_Post", true);
		register_forward(FM_GetGameDescription, "MetaForward_GameDesc_Pre"); 

		new cvarSelfGauss = get_cvar_pointer("mp_selfgauss");
		if(cvarSelfGauss)
			bind_pcvar_num(cvarSelfGauss, g_iSelfGaussType);
		else 
		{
			if(g_bIsHL25)
				g_iSelfGaussType = 1;
			else
				g_iSelfGaussType = 0;
		}

		new cvarSpawnType = get_cvar_pointer("mp_spawntype");
		if(cvarSpawnType)
			bind_pcvar_num(cvarSpawnType, g_iSpawnType);
		else
		{
			if(g_bIsHL25)
				g_iSpawnType = 0;
			else
				g_iSpawnType = 1;
		}

		new cvarBunnyHop = get_cvar_pointer("mp_bunnyhop");
		if(cvarBunnyHop)
			bind_pcvar_num(cvarBunnyHop, g_bUncappedBunny);

		if(is_plugin_loaded("flying_crowbar.amxx", true) != -1)
        	g_bCanThrowCrowbar = true;

		for(new iIndex = 0; iIndex < sizeof(g_szItems); iIndex++)
			RegisterHam(Ham_Touch, g_szItems[iIndex], "HamForward_BannedItemTouch_Pre");

		set_task(1.0, "Task_UpdateLeadingPlayers", _, _, _, "b");
	}
	else
		pause("ad");
}

public client_putinserver(iClient)
{
    if(g_bShowRuleSet && !is_user_bot(iClient))
    {
        new iBits = 0;
        new iEnd = 0;
        new aPack[2];
        aPack[0] = iBits;
        aPack[1] = iEnd;
        set_task(3.0, "Task_ShowGameRules", get_user_userid(iClient), aPack, sizeof aPack);
    }
}

public Task_ShowGameRules(const aPack[2], iUserId)
{
	new iClient = find_player_ex(FindPlayer_MatchUserId, iUserId);

	if(!iClient)
		return;

	new iBits = aPack[0];
	new iEnd = aPack[1];
	new szGameRules[MAX_HUD_MESSAGE_LENGTH];

	if(!(iBits & (1 << 0)))
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "%L^n^n", iClient, "GAMERULES_TITLE");
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 0);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 1)) && g_fCrossbowDmgMultiplier > 0.0)
	{
		new szPart[128];
		new iPercentage = floatround(g_fCrossbowDmgMultiplier * 100);
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "GAUSS_NERF_PERCENTAGE", iPercentage);
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 1);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 2)) && g_fEgonDmgMultiplier > 0.0)
	{
		new szPart[128];
		new iPercentage = floatround(g_fEgonDmgMultiplier * 100);
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "EGON_NERF_PERCENTAGE", iPercentage);
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 2);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 3)) && g_fCrossbowDmgMultiplier > 0.0)
	{
		new szPart[128];
		new iPercentage = floatround(g_fCrossbowDmgMultiplier * 100);
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "XBOW_NERF_PERCENTAGE", iPercentage);
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 3);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 4)) && g_bDisableWallGauss)
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "GAUSS_WALL_ONLY");
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 4);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 6)))
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "- %L: %L^n", iClient, "BUNNY_HOP", iClient, g_bUncappedBunny ? "BUNNY_HOP_UNCAPPED" : "BUNNY_HOP_CAPPED");
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 6);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 8)))
	{
		new szPart[128];
		new szOpt[32];
		switch(g_iSelfGaussType)
		{
			case 0:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SELF_GAUSS_ZERO");
			}
			case 1:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SELF_GAUSS_ONE");
			}
			case 2:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SELF_GAUSS_TWO");
			}
		}
		formatex(szPart, charsmax(szPart), "- %L: %s^n", iClient, "SELF_GAUSS", szOpt);
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 8);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 9)))
	{
		new szPart[128];
		new szOpt[32];
		switch(g_iSpawnType)
		{
			case 0:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SPAWN_TYPE_ZERO");
			}
			case 1:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SPAWN_TYPE_ONE");
			}
			case 2:
			{
				formatex(szOpt, charsmax(szOpt), "%L", iClient, "SPAWN_TYPE_TWO");
			}
		}
		formatex(szPart, charsmax(szPart), "- %L: %s^n", iClient, "SPAWN_TYPE", szOpt);
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 9);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 11)) && g_bSpawnProtect)
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "SPAWN_PROTECTION", floatround(g_fSpawnProtectTime));
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 11);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 12)) && g_bCanThrowCrowbar)
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "- %L^n", iClient, "FLYING_CROWBAR");
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 12);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
	}

	if(!(iBits & (1 << 13)))
	{
		new szPart[128];
		formatex(szPart, charsmax(szPart), "- %L: %L^n", iClient, "INHERITED_GAMERULES", iClient, g_bIsHL25 ? "INHERITED_GAMERULES_HL25" : "INHERITED_GAMERULES_LEGACY");
		if(strlen(szPart) + strlen(szGameRules) < MAX_HUD_MESSAGE_LENGTH)
		{
			iBits |= (1 << 13);
			add(szGameRules, charsmax(szGameRules), szPart);
		}
		iEnd = 1;
	}

	set_hudmessage(250, 244, 195, 0.05, 0.25, 0, 6.0, 12.0, 0.1, 0.2, -1);
	show_hudmessage(iClient, szGameRules);

	if(iEnd == 0)
	{
		new aPack[3];
		aPack[0] = iBits;
		aPack[1] = iEnd;
		set_task(12.0, "Task_ShowGameRules", iClient, aPack, sizeof aPack);
	}
}

public Task_UpdateLeadingPlayers() 
{
	if(!g_bStopStreak)
		return;

	new Float:fMaxKD = -1.0;
	new Float:fSecondMaxKD = -1.0;
	new iLeadingPlayer = -1;

	new rgClients[MAX_PLAYERS], iClientCount, iClient;
	get_players(rgClients, iClientCount, "h");

	for(new iIndex=0; iIndex < iClientCount; iIndex++)
	{
		iClient = rgClients[iIndex];
		g_bPlayerShouldRollForItems[iClient] = false;

		if(pev(iClient, pev_flags) & FL_SPECTATOR)
			continue;

		new iFrags = get_user_frags(iClient);
		new iDeaths = get_user_deaths(iClient);
		new Float:fKD = (iDeaths > 0) ? float(iFrags) / float(iDeaths) : float(iFrags);

		if(fKD > fMaxKD)
		{
			fSecondMaxKD = fMaxKD;
			fMaxKD = fKD;
			iLeadingPlayer = iClient;
		}
		else if(fKD > fSecondMaxKD)
			fSecondMaxKD = fKD;
	}

	if(fMaxKD - fSecondMaxKD < g_fStreakThreshold)
		iLeadingPlayer = -1;
	else
		g_bPlayerShouldRollForItems[iLeadingPlayer] = true;
}

public HamForward_GaussWeaponIdle_Pre(iGauss)
{
	// the variable is an int in the HLSDK, but it's wrongly prefixed as float
	new fInAttack = get_ent_data(iGauss, "CBaseEntity", "m_fInAttack");
	if(fInAttack != 0)
	{
		new iOwner = get_ent_data_entity(iGauss, "CBasePlayerItem", "m_pPlayer");

		if(g_iPluginFlags & AMX_FLAG_DEBUG)
			server_print("[DEBUG] %s::HamForward_GaussWeaponIdle_Pre() - Called on weapon %d (owner %n)", __BINARY__, iGauss, iOwner);

		new rgClients[MAX_PLAYERS], iClientCount, iClient;
		get_players(rgClients, iClientCount, "ah");

		for(new iIndex = 0; iIndex < iClientCount; iIndex++)
		{
			iClient = rgClients[iIndex];

			if(g_iPluginFlags & AMX_FLAG_DEBUG)
				server_print("[DEBUG] %s::HamForward_GaussWeaponIdle_Pre() - Looping clients, checking client %d (%n)", __BINARY__, iClient, iClient);

			if(iOwner != iClient && !CheckValidHit(iOwner, iClient))
				g_bShouldPreventBleeding[iClient] = true;
		}
	}
}

public HamForward_GaussWeaponIdle_Post(iGauss)
{
	for(new iClient = 1; iClient <= MaxClients; iClient++)
		g_bShouldPreventBleeding[iClient] = false;
}

public MetaForward_GameDesc_Pre()
{
	new bool:bIsCustomVariant = false; 

	if(g_bStopStreak != (str_to_num(STOP_STREAK_DEFAULT_VALUE) == 1) || g_fStreakThreshold != str_to_float(STOP_STREAK_KD_DEFAULT_VALUE) || 
		g_fStreakRollValue != str_to_float(STOP_ITEM_PERCENTAGE_DEFAULT_VALUE) || g_bDisableWallGauss != (str_to_num(DISABLE_WALLGAUSS_DEFAULT_VALUE) == 1) ||
		g_fGaussDmgMultiplier != str_to_float(GAUSS_DMG_MULTIPLIER_DEFAULT_VALUE) || g_fEgonDmgMultiplier != str_to_float(EGON_DMG_MULTIPLIER_DEFAULT_VALUE) ||
		g_fCrossbowDmgMultiplier != str_to_float(CROSSBOW_DMG_MULTIPLIER_DEFAULT_VALUE) || g_bSpawnProtect != (str_to_num(SPAWN_PROTECT_DEFAULT_VALUE) == 1) ||
		g_fSpawnProtectTime != str_to_float(SPAWN_PROTECT_DEFAULT_TIME))
		bIsCustomVariant = true;
	
	new szGameName[64];
	copy(szGameName, sizeof(szGameName), NERF_GAMENAME);
	
	if(g_bIsHL25)
		strcat(szGameName, " (HL25)", sizeof(szGameName))

	strcat(szGameName, " ", sizeof(szGameName))
	if(bIsCustomVariant)
		strcat(szGameName, " (CUSTOM)", sizeof(szGameName))
	else
	{
		strcat(szGameName, " v", sizeof(szGameName))
		strcat(szGameName, PLUGIN_VERSION, sizeof(szGameName))
	}
	
	forward_return(FMV_STRING, szGameName); 
	return FMRES_SUPERCEDE;
}  

public MetaForward_AddToFullPack_Pre(iEntState, iEnt, iEntEdict, iClient, iHostFlags, bIsEntPlayer, iVisibility) 
{
	if(!g_bIsRolling[iClient])
		return FMRES_IGNORED;

	new iBannedItem = -1;

	new szClassName[32];
	pev(iEnt, pev_classname, szClassName, charsmax(szClassName));
	for(new iIndex = 0; iIndex < sizeof(g_szItems); iIndex++)
	{
		if(equal(szClassName, g_szItems[iIndex]))
			iBannedItem = iIndex;
	}

	if(iBannedItem == -1)
		return FMRES_IGNORED;

	if(g_fPlayerItemRoll[iClient][iBannedItem] > g_fStreakRollValue)
		return FMRES_SUPERCEDE;

	return FMRES_IGNORED;
}

public MetaForward_AddToFullPack_Post(iEntState, iEnt, iEntEdict, iClient, iHostFlags, bIsEntPlayer, iVisibility) 
{
	if(!g_bIsRolling[iClient])
		return FMRES_IGNORED;

	new szClassName[32];
	pev(iEnt, pev_classname, szClassName, charsmax(szClassName));

	if(equal(szClassName, "func_recharge"))
	{
		set_es(iEntState, ES_Frame, 1.0);
		return FMRES_HANDLED;
	}

	return FMRES_IGNORED;
}

public HamForward_PlayerBloodColor_Pre(iClient)
{
	if(g_bDisableWallGauss && g_bShouldPreventBleeding[iClient])
	{
		SetHamReturnInteger(DONT_BLEED);
		return HAM_OVERRIDE;
	}
	else
		return HAM_IGNORED;
}

public HamForward_PlayerSpawn_Post(iClient)
{
	if(g_bStopStreak && g_bPlayerShouldRollForItems[iClient])
	{
		g_bIsRolling[iClient] = true;
		for(new iIndex = 0; iIndex < sizeof g_szItems; iIndex++)
			g_fPlayerItemRoll[iClient][iIndex] = random_float(0.0, 100.0);
	}
	else
		g_bIsRolling[iClient] = false;

	if(g_bSpawnProtect)
      	RequestFrame("SpawnProtect", iClient);
}

public SpawnProtect(iClient)
{
	set_user_godmode(iClient, true);
	set_user_rendering(iClient, kRenderFxGlowShell, 255, 255, 255, kRenderNormal, g_iSpawnProtectShellThickness);
	set_task(g_fSpawnProtectTime, "Task_DisableSpawnProtection", get_user_userid(iClient));
}

public Task_DisableSpawnProtection(iUserId)
{
	new iClient = find_player_ex(FindPlayer_MatchUserId, iUserId);
	
	if(!iClient)
		return;

	set_user_godmode(iClient, false);
	set_user_rendering(iClient, kRenderFxGlowShell, 0, 0, 0, kRenderNormal, 0);
}

public HamForward_PlayerTakeDamage_Pre(iVictim, iInflictor, iAttacker, Float:fDamage, iDamageBits)
{
	if(!iVictim || !iAttacker || !g_bNerfFormatEnabled || iAttacker == 0 || iAttacker > MaxClients)
		return HAM_IGNORED;
	
	new iUserWeapon = get_user_weapon(iAttacker);

	switch(iUserWeapon)
	{
		case HLW_GAUSS:
		{
			new iAiming;
			get_user_aiming(iAttacker, iAiming);
			
			if(g_bDisableWallGauss && iAttacker != iAiming && iAiming > 0 || iAiming <= MaxClients)
			{
				if(is_user_connected(iAiming)) // If directly aiming at a player, no wall needed.
				{
					SetHamParamFloat(4, fDamage*g_fGaussDmgMultiplier);
					return HAM_HANDLED;
				}
				else
				{ 
					if(CheckValidHit(iAttacker, iVictim))
						return HAM_IGNORED; // Allow damage: It's a legitimate wallgauss shot
					else
						return HAM_SUPERCEDE;
				}
			}
			else
			{
				SetHamParamFloat(4, fDamage*g_fGaussDmgMultiplier);
				return HAM_HANDLED;
			}
		}
		case HLW_CROSSBOW:
		{
			if(!(iDamageBits & DMG_BLAST))
			{
				SetHamParamFloat(4, fDamage*g_fCrossbowDmgMultiplier);
				return HAM_HANDLED;
			}
		}
		case HLW_EGON:
		{
			SetHamParamFloat(4, fDamage*g_fEgonDmgMultiplier);
			return HAM_HANDLED;
		}
	}

	return HAM_IGNORED;
}

public HamForward_BannedItemTouch_Pre(iThis, iOther)
{
    if(g_bStopStreak && 1 <= iOther <= MaxClients && g_bIsRolling[iOther])
	{
		new szClassName[MAX_NAME_LENGTH];
		pev(iThis, pev_classname, szClassName, charsmax(szClassName));
		new iBannedItem = -1;
		for(new iIndex = 0; iIndex < sizeof g_szItems; iIndex++)
		{
			if(equali(g_szItems[iIndex], szClassName))
			{
				iBannedItem = iIndex;
				break;
			}
		}

		if(iBannedItem >= 0 && g_fPlayerItemRoll[iOther][iBannedItem] > g_fStreakRollValue)
			return HAM_SUPERCEDE;
	}
    
    return HAM_IGNORED;
}

public HamForward_RechargerUse_Pre(iThis, iCaller, iActivator, iUseType, Float:fValue)
{
    if(g_bStopStreak && 1 <= iCaller <= MaxClients && g_bIsRolling[iCaller])
    {
        if(g_bCanPlayEmptySound[iCaller])
        {
            client_cmd(iCaller, "spk sound/items/suitchargeno1.wav");
            g_bCanPlayEmptySound[iCaller] = false;
            set_task(1.0, "Task_ResetEmptySound", iCaller);
        }
        return HAM_SUPERCEDE;
    }
    
    return HAM_IGNORED;
}

public Task_ResetEmptySound(iCaller)
{
    g_bCanPlayEmptySound[iCaller] = true;
}

bool:CheckValidHit(iAttacker, iVictim)
{
	if(g_iPluginFlags & AMX_FLAG_DEBUG)
		server_print("[DEBUG] %s::CheckValidHit() - Called on %n -> %n", __BINARY__, iAttacker, iVictim);

	static Float:fStart[3], Float:fDest[3], Float:fDir[3];
	pev(iAttacker, pev_origin, fStart);
	pev(iAttacker, pev_view_ofs, fDest);
	xs_vec_add(fStart, fDest, fStart);

	pev(iAttacker, pev_v_angle, fDest);
	engfunc(EngFunc_MakeVectors, fDest);

	global_get(glb_v_forward, fDir);
	xs_vec_copy(fDir, fDest); // Keep direction forbounce calculation

	xs_vec_mul_scalar(fDest, V_WALL, g_fWallSteep);
	xs_vec_mul_scalar(fDest, V_DISTANCE, fDest);
	xs_vec_add(fStart, fDest, fDest);

	// First trace - check forinitial hit
	new iHit = 0;
	new iTrace = create_tr2();
	engfunc(EngFunc_TraceLine, fStart, fDest, IGNORE_MONSTERS, iAttacker, iTrace);

	new Float:fFraction;
	get_tr2(iTrace, TR_flFraction, fFraction);

	if(fFraction < 1.0)
	{
		new iHitEnt = get_tr2(iTrace, TR_pHit);
		
		if(CanReflectGauss(iHitEnt))
		{
			if(g_iPluginFlags & AMX_FLAG_DEBUG)
				server_print("[DEBUG] %s::CheckValidHit() - %n's shot should ricochet.", __BINARY__, iAttacker);

			new Float:fNormal[3];
			get_tr2(iTrace, TR_vecPlaneNormal, fNormal);
			
			new Float:fAngle = -xs_vec_dot(fNormal, fDir);
			
			if(fAngle < 0.5)
			{
				if(g_iPluginFlags & AMX_FLAG_DEBUG)
					server_print("[DEBUG] %s::CheckValidHit() - 60 degree shot, the shot ricochet.", __BINARY__);

				new Float:fBounceDir[3], Float:fBounceStart[3];
				
				xs_vec_mul_scalar(fNormal, 2.0 * fAngle, fBounceDir);
				xs_vec_add(fBounceDir, fDir, fBounceDir);
				
				get_tr2(iTrace, TR_vecEndPos, fBounceStart);
				xs_vec_mul_scalar(fBounceDir, 8.0, fDest);
				xs_vec_add(fBounceStart, fDest, fBounceStart);
				
				xs_vec_mul_scalar(fBounceDir, 8192.0, fDest);
				xs_vec_add(fBounceStart, fDest, fDest);
				
				engfunc(EngFunc_TraceLine, fBounceStart, fDest, DONT_IGNORE_MONSTERS, iAttacker, iTrace);

				iHit = get_tr2(iTrace, TR_pHit);
				free_tr2(iTrace);
				
				if(pev_valid(iHit) && iHit == iVictim)
				{
					if(g_iPluginFlags & AMX_FLAG_DEBUG)
						server_print("[DEBUG] %s::CheckValidHit() - Bouncing shot hit the victim", __BINARY__);
					return true;
				}
					
				if(g_iPluginFlags & AMX_FLAG_DEBUG)
					server_print("[DEBUG] %s::CheckValidHit() - Bouncing shot didn't hit the victim.", __BINARY__);

				return false;
			}
		}
	}

	free_tr2(iTrace);

	new iLoop = 0;
	while(!FindTargetByTrace(iAttacker, fStart, fDest, iHit))
	{
		if(++iLoop == LOOP_ESCAPE_THRESHOLD)
			break;
	}

	if(iHit != 0 && iHit == iVictim)
	{
		if(g_iPluginFlags & AMX_FLAG_DEBUG)
			server_print("[DEBUG] %s::CheckValidHit() Pierced shot reached %n.", __BINARY__, iHit);
		return true;
	}

	return false;
}

// credits: VEN
stock bool:FindTargetByTrace(iEnt, Float:fStart[3], const Float:fDest[3], &iHit)
{
	engfunc(EngFunc_TraceLine, fStart, fDest, DONT_IGNORE_MONSTERS, iEnt, 0);

	if((iHit = get_tr2(0, TR_pHit)) > 0 && pev_valid(iHit))
		return false;

	static Float:fFraction;
	get_tr2(0, TR_flFraction, fFraction);

	if(fFraction == 1.0)
		return true;

	get_tr2(0, TR_vecEndPos, fStart);
	xs_vec_add(fStart, g_fWallSteep, fStart);

	return false;
}

CanReflectGauss(iEntity)
{
	if(g_iPluginFlags & AMX_FLAG_DEBUG)
		server_print("[DEBUG] %s::CanReflectGauss() Called on entity number %d.", __BINARY__, iEntity);

	if(iEntity == -1)
		return true; //if -1, then the entity it hits was worldspawn, then it can reflect

	return (is_valid_ent(iEntity) && ExecuteHam(Ham_ReflectGauss, iEntity)) || ExecuteHam(Ham_IsBSPModel, iEntity);
}