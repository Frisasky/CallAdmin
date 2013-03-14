#include <sourcemod>
#include <updater>
#include <autoexecconfig>
#pragma semicolon 1




// Banreasons
new Handle:g_hBanReasons;
new String:g_sBanReasons[1200];
new String:g_sBanReasonsExploded[24][48];


// Global Stuff
new Handle:g_hServerID;
new g_iServerID;

new Handle:g_hServerName;
new String:g_sServerName[64];

new Handle:g_hEntryPruning;
new g_iEntryPruning;

new Handle:g_hVersion;

new Handle:g_hHostPort;
new g_iHostPort;



// User info
new g_iTarget[MAXPLAYERS + 1];
new String:g_sTargetReason[MAXPLAYERS + 1][48];

// When has this user reported the last time
new g_iLastReport[MAXPLAYERS +1];

// When was this user reported the last time
new g_bWasReported[MAXPLAYERS +1];

// Player saw the antispam message
new bool:g_bSawMesage[MAXPLAYERS +1];


// Dbstuff
new Handle:g_hDbHandle;


#define PLUGIN_VERSION "0.1.0A"
#define SQL_DB_CONF "CallAdmin"



// Updater
#define UPDATER_URL "http://plugins.gugyclan.eu/calladmin/calladmin.txt"



public Plugin:myinfo = 
{
	name = "CallAdmin",
	author = "Impact",
	description = "Call an Admin for help",
	version = PLUGIN_VERSION,
	url = "http://gugyclan.eu"
}



public OnPluginStart()
{
	if(!SQL_CheckConfig(SQL_DB_CONF))
	{
		SetFailState("Couldn't find database config");
	}
	
	SQL_TConnect(SQLT_ConnectCallback, SQL_DB_CONF);
	
	
	g_hHostPort   = FindConVar("hostport");
	g_hServerName = FindConVar("hostname");
	
	
	// Shouldn't happen
	if(g_hHostPort == INVALID_HANDLE)
	{
		SetFailState("Couldn't find cvar 'hostport'");
	}
	if(g_hServerName == INVALID_HANDLE)
	{
		SetFailState("Couldn't find cvar 'hostname'");
	}
	
	
	RegConsoleCmd("sm_call", Command_Call);
	
	
	AutoExecConfig_SetFile("plugin.calladmin");
	
	g_hVersion       = AutoExecConfig_CreateConVar("sm_calladmin_version", PLUGIN_VERSION, "Plugin version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	g_hBanReasons    = AutoExecConfig_CreateConVar("sm_calladmin_banreasons", "Aimbot; Wallhack; Speedhack; Spinhack; Multihack; No-Recoil Hack", "Semicolon seperated list of banreasons (24 reasons max, 48 max length per reason)", FCVAR_PLUGIN);
	g_hServerID      = AutoExecConfig_CreateConVar("sm_calladmin_serverid", "-1", "Numerical unique id to use for this server, hostport will be used if value is below 0", FCVAR_PLUGIN);
	g_hEntryPruning  = AutoExecConfig_CreateConVar("sm_calladmin_entrypruning", "1800", "Entries older than given minuten will be deleted, 0 deactivates the feature", FCVAR_PLUGIN, true, 0.0, true, 3600.0);
	
	
	AutoExecConfig(true, "plugin.calladmin");
	AutoExecConfig_CleanFile();
	
	
	LoadTranslations("calladmin.phrases");
	
	
	SetConVarString(g_hVersion, PLUGIN_VERSION, false, false);
	HookConVarChange(g_hVersion, OnCvarChanged);
	
	
	GetConVarString(g_hBanReasons, g_sBanReasons, sizeof(g_sBanReasons));
	ExplodeString(g_sBanReasons, ";", g_sBanReasonsExploded, sizeof(g_sBanReasonsExploded), sizeof(g_sBanReasonsExploded[]), true);
	HookConVarChange(g_hBanReasons, OnCvarChanged);
	
	g_iServerID = GetConVarInt(g_hServerID);
	HookConVarChange(g_hServerID, OnCvarChanged);
	
	GetConVarString(g_hServerName, g_sServerName, sizeof(g_sServerName));
	HookConVarChange(g_hServerName, OnCvarChanged);
	
	g_iHostPort = GetConVarInt(g_hHostPort);
	HookConVarChange(g_hHostPort, OnCvarChanged);
	
	g_iEntryPruning = GetConVarInt(g_hEntryPruning);
	HookConVarChange(g_hEntryPruning, OnCvarChanged);
	
	
	// Check ServerID for default
	if(g_iServerID < 0)
	{
		g_iServerID = g_iHostPort;
	}
	
	CreateTimer(600.0, Timer_PruneEntries, _, TIMER_REPEAT);
}




public OnAllPluginsLoaded()
{
    if(LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATER_URL);
    }
}




public OnLibraryAdded(const String:name[])
{
    if(StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATER_URL);
    }
}




public Action:Timer_PruneEntries(Handle:timer)
{
	// Prune old entries if enabled
	if(g_iEntryPruning > 0)
	{
		PruneDatabase();
	}
	
	return Plugin_Continue;
}




PruneDatabase()
{
	if(g_hDbHandle != INVALID_HANDLE)
	{
		decl String:query[1024];
		Format(query, sizeof(query), "DELETE FROM CallAdmin WHERE serverID = '%d' AND TIMESTAMPDIFF(MINUTE, FROM_UNIXTIME(reportedAt), FROM_UNIXTIME(%d)) > %d", g_iServerID, GetTime(), g_iEntryPruning);
		SQL_TQuery(g_hDbHandle, SQLT_ErrorCheckCallback, query);
	}
}




UpdateServerData()
{
	if(g_hDbHandle != INVALID_HANDLE)
	{
		decl String:query[1024];
		decl String:sHostName[(sizeof(g_sServerName)+1) * 2];
		SQL_EscapeString(g_hDbHandle, g_sServerName, sHostName, sizeof(sHostName));
		
		// Update the servername
		Format(query, sizeof(query), "UPDATE IGNORE CallAdmin SET serverName = '%s' WHERE serverID = '%d'", sHostName, g_iServerID);
		SQL_TQuery(g_hDbHandle, SQLT_ErrorCheckCallback, query);
	}
}




public OnCvarChanged(Handle:cvar, const String:oldValue[], const String:newValue[])
{
	if(cvar == g_hBanReasons)
	{
		GetConVarString(g_hBanReasons, g_sBanReasons, sizeof(g_sBanReasons));
		ExplodeString(g_sBanReasons, ";", g_sBanReasonsExploded, sizeof(g_sBanReasonsExploded), sizeof(g_sBanReasonsExploded[]), true);
	}
	else if(cvar == g_hServerID)
	{
		g_iServerID = GetConVarInt(g_hServerID);
		
		// Check for empty value
		if(g_iServerID < 0)
		{
			g_iServerID = g_iHostPort;
		}
	}
	else if(cvar == g_hHostPort)
	{
		g_iHostPort = GetConVarInt(g_hHostPort);
	}
	else if(cvar == g_hServerName)
	{
		GetConVarString(g_hServerName, g_sServerName, sizeof(g_sServerName));
		UpdateServerData();
	}
	else if(cvar == g_hEntryPruning)
	{
		g_iEntryPruning = GetConVarInt(g_hEntryPruning);
	}
	else if(cvar == g_hVersion)
	{
		SetConVarString(g_hVersion, PLUGIN_VERSION, false, false);
	}
}




public Action:Command_Call(client, args)
{
	if(g_iLastReport[client] == 0 || g_iLastReport[client] <= ( GetTime() - 10 ))
	{
		g_bSawMesage[client] = false;
		ShowClientSelectMenu(client);
	}
	else if(!g_bSawMesage[client])
	{
		PrintToChat(client, "\x03 %t", "CallAdmin_CommandNotAllowed", 10 - ( GetTime() - g_iLastReport[client] ));
		g_bSawMesage[client] = true;
	}

	return Plugin_Handled;
}




ReportPlayer(client, target)
{
	new String:clientNameBuf[MAX_NAME_LENGTH];
	new String:clientName[(MAX_NAME_LENGTH * 2) + 1];
	new String:clientAuth[21];
	
	new String:targetNameBuf[MAX_NAME_LENGTH];
	new String:targetName[(MAX_NAME_LENGTH * 2) + 1];
	new String:targetAuth[21];
	
	new String:sReason[(48 * 2) +1];
	SQL_EscapeString(g_hDbHandle, g_sTargetReason[client], sReason, sizeof(sReason));
	
	
	GetClientName(client, clientNameBuf, sizeof(clientNameBuf));
	SQL_EscapeString(g_hDbHandle, clientNameBuf, clientName, sizeof(clientName));
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));
	
	GetClientName(target, targetNameBuf, sizeof(targetNameBuf));
	SQL_EscapeString(g_hDbHandle, targetNameBuf, targetName, sizeof(targetName));
	GetClientAuthString(target, targetAuth, sizeof(targetAuth));
	
	new String:serverName[(sizeof(g_sServerName) *2) + 1];
	SQL_EscapeString(g_hDbHandle, g_sServerName, serverName, sizeof(serverName));
	
	new String:query[1024];
	Format(query, sizeof(query), "INSERT INTO CallAdmin VALUES ('%d', '%s', '%s', '%s', '%s', '%s', '%s', '%d')", g_iServerID, serverName, targetName, targetAuth, sReason, clientName, clientAuth, GetTime());
	SQL_TQuery(g_hDbHandle, SQLT_ErrorCheckCallback, query);
	
	PrintToChatAll("\x03 %t", "CallAdmin_HasReported", clientNameBuf, targetNameBuf, sReason);
	g_iLastReport[client]   = GetTime();
	g_bWasReported[target]  = true;
}





public SQLT_ConnectCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		SetFailState("ConErr: %s", error);
	}
	else
	{
		g_hDbHandle = hndl;
		
		
		// Create Table
		SQL_TQuery(g_hDbHandle, SQLT_ErrorCheckCallback, "CREATE TABLE IF NOT EXISTS `CallAdmin` (\
															`serverID` SMALLINT UNSIGNED NOT NULL,\
															`serverName` VARCHAR(64) NOT NULL,\
															`targetName` VARCHAR(32) NOT NULL,\
															`targetID` VARCHAR(21) NOT NULL,\
															`targetReason` VARCHAR(48) NOT NULL,\
															`clientName` VARCHAR(32) NOT NULL,\
															`clientID` VARCHAR(21) NOT NULL,\
															`reportedAt` INT(10) UNSIGNED NOT NULL,\
															INDEX `reportedAt` (`reportedAt`))\
														COLLATE='utf8_unicode_ci'\
														ENGINE=MyISAM;\
														");
		
		// Prune old entries if enabled
		if(g_iEntryPruning > 0)
		{
			PruneDatabase();
		}
		
		// Update Serverdata
		UpdateServerData();
	}
}





public SQLT_ErrorCheckCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		SetFailState("QueryErr: %s", error);
	}
}





ShowClientSelectMenu(client)
{
	decl String:sName[MAX_NAME_LENGTH];
	decl String:sID[24];
	
	new Handle:menu = CreateMenu(MenuHandler_ClientSelect);
	SetMenuTitle(menu, "%T", "CallAdmin_SelectClient", client);
	
	for(new i; i <= MaxClients; i++)
	{
		if(client != i && !g_bWasReported[i] && IsClientValid(i) )
		{
			GetClientName(i, sName, sizeof(sName));
			Format(sID, sizeof(sID), "%d", GetClientSerial(i));
			
			AddMenuItem(menu, sID, sName);
		}
	}
	
	if(GetMenuItemCount(menu) < 1)
	{
		PrintToChat(client, "\x03 %t", "CallAdmin_NoPlayers");
		g_iLastReport[client] = GetTime();
	}
	else
	{
		DisplayMenu(menu, client, 30);
	}
}




public MenuHandler_ClientSelect(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		new String:sInfo[24];
		new iSerial;
		new iID;
		
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		iSerial = StringToInt(sInfo);
		iID     = GetClientFromSerial(iSerial);
		
		
		if(IsClientValid(iID))
		{
			g_iTarget[client] = iID;
			
			ShowBanreasonMenu(client);
		}
		else
		{
			PrintToChat(client, "\x03 %t", "CallAdmin_NotInGame");
		}
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}





public OnClientDisconnect_Post(client)
{
	g_iTarget[client]          = 0;
	g_sTargetReason[client][0] = '\0';
	g_iLastReport[client]      = 0;
	g_bWasReported[client]     = false;
	g_bSawMesage[client]       = false;
	
	RemoveAsTarget(client);
}




RemoveAsTarget(client)
{
	for(new i; i <= MaxClients; i++)
	{
		if(g_iTarget[i] == client)
		{
			g_iTarget[i] = 0;
		}
	}
}




ShowBanreasonMenu(client)
{
	new count;
	
	count = sizeof(g_sBanReasonsExploded);

	
	new Handle:menu = CreateMenu(MenuHandler_BanReason);
	SetMenuTitle(menu, "%T", "CallAdmin_SelectReason", client, g_iTarget[client]);
	
	new index;
	for(new i; i < count; i++)
	{
		if(strlen(g_sBanReasonsExploded[i]) < 1)
		{
			continue;
		}
		
		index = 0;
		if(g_sBanReasonsExploded[i][0] == ' ')
		{
			index = 1;
		}
		
		AddMenuItem(menu, g_sBanReasonsExploded[i][index], g_sBanReasonsExploded[i][index]);
	}
	
	DisplayMenu(menu, client, 30);
}




public MenuHandler_BanReason(Handle:menu, MenuAction:action, client, param2)
{
	if(action == MenuAction_Select)
	{
		new String:sInfo[48];
		GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
		
		Format(g_sTargetReason[client], sizeof(g_sTargetReason[]), sInfo);
		
		
		if(IsClientValid(g_iTarget[client]))
		{
			// Send the report
			ReportPlayer(client, g_iTarget[client]);
		}
		else
		{
			PrintToChat(client, "\x03 %t", "CallAdmin_NotInGame");
		}
	}
	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}




stock bool:IsClientValid(id)
{
	if(id > 0 && id <= MaxClients && IsClientInGame(id))
	{
		return true;
	}
	
	return false;
}
