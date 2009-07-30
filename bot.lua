BOT_VERSION = 2.45;

include("database.lua");
include("addresses.lua");
include("classes/player.lua");
include("classes/camera.lua");
include("classes/waypoint.lua");
include("classes/waypointlist.lua");
include("classes/waypointlist_wander.lua");
include("classes/node.lua");
include("functions.lua");
include("settings.lua");


DEBUG_ASSERT = false; -- Change to 'true' to debug memory reading problems.

settings.load();
setStartKey(settings.hotkeys.START_BOT.key);
setStopKey(settings.hotkeys.STOP_BOT.key);



__WPL = nil; -- Way Point List
__RPL = nil; -- Return Point List


print("\n\169\83\111\108\97\114\83\116\114\105\107\101\32" ..
"\83\111\102\116\119\97\114\101\44\32\119\119\119\46\115" ..
"\111\108\97\114\115\116\114\105\107\101\46\110\101\116\n");
function main()
	local forcedProfile = nil;
	local forcedPath = nil;
	local forcedRetPath = nil;

	for i = 2,#args do
		if( args[i] == "update" ) then
			include("update.lua");
		end

		local foundpos = string.find(args[i], ":", 1, true);
		if( foundpos ) then
			local var = string.sub(args[i], 1, foundpos-1);
			local val = string.sub(args[i], foundpos+1);

			if( var == "profile" ) then
				forcedProfile = val;
			elseif( var == "path" ) then
				forcedPath = val;
			elseif( var == "retpath" ) then
				forcedRetPath = val;
			end
		end
	end

	local versionMsg = sprintf("RoM Bot Version %0.2f", BOT_VERSION);
	cprintf(cli.lightblue, versionMsg .. "\n");
	logMessage(versionMsg);

	-- Load "english" first, to fill in any gaps in the users' set language.
	local function setLanguage(name)
		include(getExecutionPath() .. "/language/" .. name .. ".lua");
	end

	local lang_base = {};
	setLanguage("english");
	for i,v in pairs(language) do lang_base[i] = v; end;
	setLanguage(settings.options.LANGUAGE);
	for i,v in pairs(lang_base) do
		if( language[i] == nil ) then
			language[i] = v;
		end
	end;
	lang_base = nil; -- Not needed anymore, destroy it.
	logMessage("Language: " .. settings.options.LANGUAGE);

	database.load();

	attach(getWin());

	if( not checkExecutableCompatible() ) then
		cprintf(cli.yellow, "!! Notice: !!\n");
		printf("The game may have been updated or altered.\n" ..
			"It is recommended that you run rom/update.lua\n\n");

		logMessage("Game exectuable may have changed. You should run rom/update.lua");
	end



	local playerAddress = memoryReadIntPtr(getProc(), staticcharbase_address, charPtr_offset);
	printf("Attempt to read playerAddress\n");

	if( playerAddress == nil ) then playerAddress = 0; end;
	logMessage(sprintf("Using static char address 0x%X, player address 0x%X",
		tonumber(staticcharbase_address), tonumber(playerAddress)));

	player = CPlayer(playerAddress);
	player:initialize();
	player:update();

	local cameraAddress = memoryReadIntPtr(getProc(), staticcharbase_address, camPtr_offset);
	if( cameraAddress == nil ) then cameraAddress = 0; end;

	camera = CCamera(cameraAddress);

	mousePawn = CPawn( memoryReadIntPtr(getProc(), staticcharbase_address, mousePtr_offset) );
	printf("mousePawn: 0x%X\n", mousePawn.Address);

	printf("playerAddr: 0x%X\n", player.Address);
	printf("playerTarget: 0x%X\n", player.TargetPtr);

	-- Set window name, install timer to automatically do it once a second
	if( forcedProfile ) then
		setWindowName(getHwnd(), sprintf("RoM Bot %s [%s]", BOT_VERSION, forcedProfile));
		settings.loadProfile(forcedProfile);
		registerTimer("timedSetWindowName", secondsToTimer(1), timedSetWindowName, forcedProfile);
	else
		settings.loadProfile(player.Name);
		setWindowName(getHwnd(), sprintf("RoM Bot %s [%s]", BOT_VERSION, player.Name));
		registerTimer("timedSetWindowName", secondsToTimer(1), timedSetWindowName, player.Name);
	end

	if( settings.profile.options.PATH_TYPE == "wander" or forcedPath == "wander" ) then
		__WPL = CWaypointListWander();
		__WPL:setRadius(settings.profile.options.WANDER_RADIUS);
		__WPL:setMode("wander");
	elseif( settings.profile.options.PATH_TYPE == "waypoints" or forcedPath ) then
		__WPL = CWaypointList();
	else
		error("Unknown PATH_TYPE in profile.", 0);
	end


	-- This logic prevents files from being loaded if wandering was forced
	if( forcedPath and not (forcedPath == "wander") ) then
		__WPL = CWaypointList();
		__WPL:load(getExecutionPath() .. "/waypoints/" .. forcedPath .. ".xml");
	else
		if( settings.profile.options.WAYPOINTS ) then
			__WPL:load(getExecutionPath() .. "/waypoints/" .. settings.profile.options.WAYPOINTS);
		end
	end

	if( forcedRetPath ) then
		__RPL = CWaypointList();
		__RPL:load(getExecutionPath() .. "/waypoints/" .. forcedRetPath .. ".xml");
	else
		if( settings.profile.options.RETURNPATH ) then
			__RPL = CWaypointList();
			__RPL:load(getExecutionPath() .. "/waypoints/" .. settings.profile.options.RETURNPATH);
		end
	end

	-- Output filename only if mode isnt set to wandering
	if not( __WPL:getMode() == "wander" )	then
		cprintf(cli.green, language[0], __WPL:getFileName());
	end

	if( __RPL and __RPL:getFileName() ) then
		cprintf(cli.green, language[1], __RPL:getFileName());
	end
	
	-- special option for use waypoint file in a reverse order
	if( settings.profile.options.WAYPOINTS_REVERSE == true ) then 
		__WPL:reverse();
	end;
	
	-- look for the closest waypoint / return path point to start
	if( __RPL ) then	-- return path points available ?
		-- compare closest waypoint with closest returnpath point
		__WPL:setWaypointIndex( __WPL:getNearestWaypoint(player.X, player.Z ) );
		local wp = __WPL:getNextWaypoint();
		local dist_to_wp = distance(player.X, player.Z, wp.X, wp.Z)
		
		__RPL:setWaypointIndex( __RPL:getNearestWaypoint(player.X, player.Z ) );
		local wp = __RPL:getNextWaypoint();
		local dist_to_rp = distance(player.X, player.Z, wp.X, wp.Z)
		
		if( dist_to_rp < dist_to_wp ) then	-- returnpoint is closer then next normal wayoiint
			player.Returning = true;	-- then use return path first
			cprintf(cli.yellow, language[12]);	-- Starting with return path
		else
			player.Returning = false;	-- use normale waypoint path
		end;
	else
		-- no return path available, so we select the closest normal wayoint
		__WPL:setWaypointIndex( __WPL:getNearestWaypoint(player.X, player.Z ) );
	end;
	

	local distBreakCount = 0; -- If exceedes 3 in a row, unstick.
	while(true) do
		player:update();
		player:logoutCheck();

		if( not player.Alive ) then
			-- Make sure they aren't still trying to run off
			keyboardRelease(settings.hotkeys.MOVE_FORWARD.key);
			keyboardRelease(settings.hotkeys.MOVE_BACKWARD.key);
			keyboardRelease(settings.hotkeys.ROTATE_LEFT.key);
			keyboardRelease(settings.hotkeys.ROTATE_RIGHT.key);
			keyboardRelease(settings.hotkeys.STRAFF_LEFT.key);
			keyboardRelease(settings.hotkeys.STRAFF_RIGHT.key);

			-- Take a screenshot. Only works on MicroMacro 1.0 or newer
			if( getVersion() >= 100 ) then
				showWindow(getWin(), sw.show);
				yrest(500);
				local sfn = getExecutionPath() .. "/profiles/" .. player.Name .. ".bmp";
				saveScreenshot(getWin(), sfn);
				printf(language[2], sfn);
			end

			if( type(settings.profile.events.onDeath) == "function" ) then
				local status,err = pcall(settings.profile.events.onDeath);
				if( status == false ) then
					local msg = sprintf("onDeath error: %s", err);
					error(msg);
				end
			end


			if( settings.profile.hotkeys.RES_MACRO ) then
				cprintf(cli.red, language[3]);
				keyboardPress(settings.profile.hotkeys.RES_MACRO.key);
				yrest(5000);

				if( player.Level > 9 ) then
					cprintf(cli.red, language[4]);
					yrest(60000); -- wait 1 minute before going about your path.
				end;
				player:update();

				if( not player.Alive ) then
					cprintf(cli.yellow, "You are still death. There is a problem with automatic reanimation. Did you set your ingame makro \'/script AcceptResurrect();\' to the key %s?\n", getKeyName(settings.profile.hotkeys.RES_MACRO.key));
					pauseOnDeath();
				end;

			end

			-- print out the reasons for not automatic returning
			if( not settings.profile.hotkeys.RES_MACRO ) then
				cprintf(cli.yellow, "You don't have a RES_MACRO defined in your profile! Hence no automatic returning.\n");
			end
--			if(player.Returning) then
--				cprintf(cli.yellow, "You are allready on the return path. Seems you died while returning. Hence no automatic returning.\n");
--			end
			if(__RPL == nil) then
				cprintf(cli.yellow, "You don't have a defined return path in your profile. Hence no automatic returning.1\n");
			end

			-- Must have a resurrect macro and waypoints set to be able to use
			-- a return path!
			if( settings.profile.hotkeys.RES_MACRO and
--			if( settings.profile.hotkeys.RES_MACRO and player.Returning == false and
			__RPL ~= nil ) then
				player.Returning = true;
				__RPL:setWaypointIndex(1); -- Start from the beginning

				player.Death_counter = player.Death_counter + 1;
				cprintf(cli.yellow, "You died %s times from at most %s deaths/automatic reanimations.\n", player.Death_counter, settings.profile.options.MAX_DEATHS);
				-- check maximal death if automatic mode
				if( player.Death_counter > settings.profile.options.MAX_DEATHS ) then
					player:logout();
				end
			else
				pauseOnDeath();
			end
		end

		if( player.TargetPtr ~= 0 and not player:haveTarget() ) then
			player:clearTarget();
		end


		-- go back to sleep, if in sleep mode
		if( player.Sleeping == true ) then
			yrest(800);	-- wait a little for the aggro flag
			player:update();
			if( player.Battling == false ) then 
				player:sleep(); 
			end;
		end;	-- go sleeping if sleeping flag is set


		-- rest after getting new target and before starting fight
		-- rest between 50 until 99 sec, at most until full, after that additional rnd(10)
		if( player:haveTarget() ) then	
			player:rest( 50, 99, "full", 10 );			-- rest befor next fight
		end;


		-- if aggro then wait for target from client
		-- we come back to that coding place if we stop moving because of aggro
		local aggroWaitStart = os.time();
		local msg_print = false;
		while(player.Battling) do
			-- wait a second with the aggro message to avoid wrong msg because of slow battle flag from the client
			if( msg_print == false  and  os.difftime(os.time(), aggroWaitStart) > 1 ) then
				cprintf(cli.green, language[35]);	-- Waiting on aggressive enemies.
				msg_print = true;
			end;
			if( player:haveTarget() ) then
				if( msg_print == false ) then
					cprintf(cli.green, language[35]);	-- Waiting on aggressive enemies.
					msg_print = true;
				end;

				break;
			end;

			if( os.difftime(os.time(), aggroWaitStart) > 3 ) then
				cprintf(cli.red, language[34]);
				player.LastAggroTimout = os.time();	-- remeber aggro timeout
				break;
			end;

			yrest(10);
			player:update();
		end


		if( player:haveTarget() ) then
		-- fight the mob / target
			local target = player:getTarget();
			if( settings.profile.options.ANTI_KS ) then
				if( target:haveTarget() and target:getTarget().Address ~= player.Address and (not player:isFriend(CPawn(target.TargetPtr))) ) then
					cprintf(cli.red, language[5], target.Name);
				else
					player:fight();
				end
			else
				player:fight();
			end

-- if I understand right, thats the wait stuff if we get another mob while in the fight function
-- would say we handle the 'wait for target' stuff outside the 'player:haveTarget ...
-- means before, because thats also the place to wait if we get aggro while in the moving function
--			player:update();
--			if( player.Battling ) then
--				cprintf(cli.green, language[35]);
--			end;
--
--			local aggroWaitStart = os.time();
--			while(player.Battling) do
--				if( player:haveTarget() ) then
--					break;
--				end;
--
--				if( os.difftime(os.time(), aggroWaitStart) > 3 ) then
--					cprintf(cli.red, language[34]);
--					break;
--				end;
--
--				yrest(10);
--				player:update();
--			end
		else
		-- not target, move to wp
			local wp = nil; local wpnum = nil;

			if( player.Returning ) then
				wp = __RPL:getNextWaypoint();
				wpnum = __RPL.CurrentWaypoint;
				cprintf(cli.green, language[13], wpnum, wp.X, wp.Z);	-- Moving to returnpath waypoint
			else
				wp = __WPL:getNextWaypoint();
				wpnum = __WPL.CurrentWaypoint;
				cprintf(cli.green, language[6], wpnum, wp.X, wp.Z);	-- Moving to waypoint
			end;

			local success, reason = player:moveTo(wp);


			if( player.TargetPtr ~= 0 and (not player:haveTarget()) ) then
				player:clearTarget();
			end

			if( player.TargetPtr == 0 ) then
				player:checkPotions();
				player:checkSkills( STARGET_SELF );	-- only cast friendly spells to ourselfe
			end
		

			if( success ) then
				-- if we stick directly at a wp the counter would reseted even if we are sticked
				-- hence we reset the counter only after 3 successfull waypoints
				player.Success_waypoints = player.Success_waypoints + 1;
				if( player.Success_waypoints > 3 ) then
					player.Unstick_counter = 0;	-- reset unstick counter
				end;

				if( player.Returning ) then
					-- Completed. Return to normal waypoints.
					if( __RPL.CurrentWaypoint >= #__RPL.Waypoints ) then
						__WPL:setWaypointIndex(__WPL:getNearestWaypoint(player.X, player.Z));
						player.Returning = false;
						cprintf(cli.yellow, language[7]);
					else
						__RPL:advance();
					end
				else
					__WPL:advance();
				end
			else
				if( not reason == WF_TARGET ) then
					cprintf(cli.red, language[8]);		-- Waypoint movement failed
				end

				if( reason == WF_COMBAT ) then	
					cprintf(cli.turquoise, language[14]);	-- We get aggro. Stop moving to waypoint 
				end;

				if( reason == WF_DIST ) then
					distBreakCount = distBreakCount + 1;
				else
					if( distBreakCount > 0 ) then
						distBreakCount = 0;
					end
				end

				if( reason == WF_STUCK or distBreakCount > 3 ) then
					-- Get ourselves unstuck, then!
					cprintf(cli.red, language[9]);
					distBreakCount = 0;
					player:clearTarget();
					player.Success_waypoints = 0;	-- counter for successfull waypoints in row
					player.Unstick_counter = player.Unstick_counter + 1;	-- count our unstick tries
					if( player.Unstick_counter > settings.profile.options.MAX_UNSTICK_TRIALS ) then player:logout(); end;	-- to many tries, logout
					player:unstick();
				end
			end

			coroutine.yield();

		end
	end
	
end
startMacro(main);