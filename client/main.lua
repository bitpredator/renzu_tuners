
lib.onCache('vehicle', function(value)
	invehicle = value
	if not DoesEntityExist(value) then return end
	local plate = string.gsub(GetVehicleNumberPlateText(value), '^%s*(.-)%s*$', '%1'):upper()
	GetVehicleServerStates(plate)
	--local vehiclestats = GlobalState.vehiclestats
    local coord = GetEntityCoords(value)
    local lastcoord = nil
	local ent = value and Entity(value).state
	local turbo = ent.turbo?.turbo -- renzu_turbo states bag
	local ecu_state = GlobalState.ecu
	local isdriver = GetPedInVehicleSeat(value,-1) == cache.ped
	local turbopower = 1.0
	local turboinstall = GetResourceState('renzu_turbo') == 'started'
	if not isdriver then return end
	if value then
		DefaultSetting(value)
		plate = string.gsub(GetVehicleNumberPlateText(value), '^%s*(.-)%s*$', '%1'):upper()
		LoadVehicleSetup(value,ent,vehiclestats)
		--print("setup",value ~= 0 , tonumber(value) , ecu , invehicle)
		ecu = ecu_state[plate] and ecu_state[plate].active?.boostpergear
		Citizen.CreateThreadNow(function()
			local lockspeed = 0
			local driveforce = GetVehicleHandlingFloat(value,'CHandlingData', 'fInitialDriveForce')
			local hasracingcam = ent['racing_camshaft']
			upgrade, stats = GetEngineUpgrades(value) -- get current upgraded parts
			tune = GetTuningData(plate) -- get current tuned data
			while invehicle do
				local sleep = 200
				local Speed = GetEntitySpeed(value)
				turbopower = GetVehicleCheatPowerIncrease(value)
				efficiency = EngineEfficiency(value,stats,tune,turbopower)
				local gear = GetVehicleCurrentGear(value) + 1
				if ecu and ecu[gear-1] and not indyno and turboinstall then
					exports.renzu_turbo:BoostPerGear(ecu[gear-1] or 1.0)
				end
				local rpm = GetVehicleCurrentRpm(value)
				if hasracingcam then
					if rpm >= 0.61 then -- activate high cam lobe
						SetVehicleHandlingField(value, 'CHandlingData', 'fInitialDriveForce', driveforce+(1.00/gear))
					else
						SetVehicleHandlingField(value, 'CHandlingData', 'fInitialDriveForce', driveforce+0.0)
					end
				end
				Wait(sleep)
			end
		end)
	end
	Citizen.CreateThreadNow(function()
		local tune = GetTuningData(plate)
		local upgraded = {}
		for k,v in pairs(config.engineupgrades) do -- create a list of upgraded states
			if ent and ent[v.item] then
				upgraded[v.state] = true
			end
		end
		--local vehiclestats = GlobalState.vehiclestats
		local synctimer = 0
        while value ~= 0 and tonumber(value) and invehicle do
			local ent = ent
			local sleep = ent.nitroenable and 200 or 3000
			local rpm = GetVehicleCurrentRpm(value)
			if rpm > 0.5 then -- start degrading states if its above 0.5 RPM
				local mileage = ent.mileage or 0
				local update = false
				local nitro = ent.nitroenable -- renzu_nitro states bag if nitro is being used
				local turbodeduct = 1.0
				local nitrodeduct = 1.0
				local chance = nitro and 10 or 20
				if turbo then
					turbodeduct = turbopower
				end
				if nitro then
					nitrodeduct = turbopower -- fix degration for now when using NOS
				end
				local chance_degrade = math.random(1,100) < chance
				synctimer += 1
				local resettimer = false
				for _,v2 in pairs(config.engineparts) do
					local stock = not upgraded[v2.item]	
					for k,v in ipairs(config.degrade) do
						local mileage_degration = mileage >= v.min
						local candegrade = mileage and mileage > 1000 and mileage_degration and chance_degrade -- chances of degration and conditions
						for k,handlingname in pairs(v2.handling) do
							if candegrade or (tune[handlingname] or 1.0) > 1.0 and chance_degrade and mileage_degration or turbo and chance_degrade and mileage_degration or nitro and mileage_degration and chance_degrade then
								local efficiency_degrade = 1.0 + (1.0 - efficiency)
								local stock_degrade = stock and 1.5 or efficiency_degrade -- if parts are stock degration is higher when using turbos, nitros and ECU over tunes.
								local upgraded_degrade = stock and 1.0 or (efficiency_degrade * 0.9) -- if parts are upgraded degration is lower compared to stock when using turbos, nitros and ECU over tunes.
								local degrade = v2.state ~= 'oem_suspension' and ((((v.degrade * upgraded_degrade) * (turbodeduct * stock_degrade)) * (nitrodeduct * stock_degrade)) * (efficiency_degrade * stock_degrade) * rpm) or 1.0
								ent:set(v2.item, ent[v2.item] and ent[v2.item] - degrade or vehiclestats[plate] and vehiclestats[plate][v2.item] and vehiclestats[plate][v2.item] - degrade or 100 - degrade, synctimer > 20) -- set local state bag
								resettimer = true
								break
							end
						end
					end
				end
				if synctimer > 20 and resettimer then
					synctimer = 0
					resettimer = false
				end
				HandleEngineDegration(value,ent,plate) -- handle Overall Handling and degration
			end
			Wait(sleep)
			if cache.vehicle ~= value then
				break
			end
		end
		-- on vehicle out
		for _,v2 in pairs(config.engineparts) do
			ent:set(v2.item, ent[v2.item] and ent[v2.item]+0.01, true) -- sync local state bag to server
		end
	end)
	

	local coord = GetEntityCoords(value)
    local lastcoord = nil
	Citizen.CreateThreadNow(function() -- mileage setter. this is not realistic mileage computation. this only adds +1 for every 4000 tick as default
        while value ~= 0 and tonumber(value) and GetPedInVehicleSeat(value,-1) == cache.ped do
			coord = GetEntityCoords(value)
			if lastcoord and #(coord - lastcoord) > 1 or lastcoord == nil then
				local ent = Entity(value).state
				local plate = string.gsub(GetVehicleNumberPlateText(value), '^%s*(.-)%s*$', '%1'):upper()
				if ent.mileage then
					ent:set('mileage', ent.mileage+1, true)
				elseif mileages[plate] then
					ent:set('mileage', tonumber(mileages[plate]), true)
					lastcoord = GetEntityCoords(value)
				else
					ent:set('mileage', 0, true)
					lastcoord = GetEntityCoords(value)
				end
			end
			lastcoord = GetEntityCoords(value)
			Wait(4000) -- if you want faster mileage make this lower, if you want slower mileage, make this higher
			if cache.vehicle ~= value then
				break
			end
		end
	end)
end)

Citizen.CreateThreadNow(function()
	SetDefaultVehicleNumberPlateTextPattern(-1, config.plateformat)
	if not config.usetarget then
		for k,v in pairs(config.points) do
			SetupUpgradePoints(v,k)
		end
	end
end)

Citizen.CreateThread(EngineSwaps)
Citizen.CreateThread(Crafting)

Citizen.CreateThreadNow(function()
	Wait(2000)
	local rampmodel = `prop_spray_jackframe`
	local winch = `prop_bison_winch`
	lib.requestModel(rampmodel)
	lib.requestModel(winch)
	for k,v in pairs(config.dynopoints) do
		for k,v in pairs(v.winch) do
			winch_entity = CreateObjectNoOffset(winch,v.x,v.y,v.z,true,true)
			while not DoesEntityExist(winch_entity) do Wait(1) end
			FreezeEntityPosition(winch_entity,true)
			SetEntityHeading(winch_entity,v.w)
			DisableVehicleWorldCollision(winch_entity)
			SetEntityCollision(winch_entity,false,true)
			table.insert(winches,winch_entity)
		end
		SetupDynoPoints(v,k)
	end
end)

Citizen.CreateThreadNow(function()
	Wait(1000)
	if not config.usetarget then
		for k,v in pairs(config.repairpoints) do
			SetupRepairPoints(v,k)
		end
	end
end)

Citizen.CreateThreadNow(function()
	if GetResourceState('renzu_turbo') == 'started' then
		turboconfig = exports.renzu_turbo:turbos()
	end
end)