/**
 * A connection is a link between two nodes (industries or towns) and holds all information that is
 * relevant to maintain / build such a connection. Connection are build up from ConnectionNodes. 
 * Because multiple advisors can reason over connection and create reports for them, we store the
 * best report produced by an advisor in the bestReport variable which can only be overwritten if
 * it becomes invalidated (i.e. it can't be build) or an advisor comes with a better report.
 */
class Connection {

	// Type of connection.
	static INDUSTRY_TO_INDUSTRY = 1;
	static INDUSTRY_TO_TOWN = 2;
	static TOWN_TO_TOWN = 3;
	static TOWN_TO_SELF = 4;
	
	// Vehicle types in this connection.
	vehicleTypes = null;
	
	lastChecked = null;             // The latest date this connection was inspected.
	connectionType = null;          // The type of connection (one of above).
	cargoID = null;	                // The type of cargo carried from one node to another.
	travelFromNode = null;          // The node the cargo is carried from.
	travelToNode = null;            // The node the cargo is carried to.
	vehicleGroupID = null;          // The AIGroup of all vehicles serving this connection.
	pathInfo = null;                // PathInfo class which contains all information about the path.
	bilateralConnection = null;     // If this is true, cargo is carried in both directions.
	connectionManager = null;       // Updates are send to all listeners when connection is realised, demolished or updated.

	forceReplan = null;		// Force this connection to be replanned.
	
	bestTransportEngine = null;
	bestHoldingEngine = null;
	
	constructor(cargo_id, travel_from_node, travel_to_node, path_info, connection_manager) {
		//Log.logDebug("Init Connection");
		cargoID = cargo_id;
		travelFromNode = travel_from_node;
		travelToNode = travel_to_node;
		pathInfo = path_info;
		connectionManager = connection_manager;
		forceReplan = false;
		bilateralConnection = travel_from_node.GetProduction(cargo_id) > 0 && travel_to_node.GetProduction(cargo_id) > 0;
		
		if (travelFromNode.nodeType == ConnectionNode.INDUSTRY_NODE) {
			if (travelToNode.nodeType == ConnectionNode.INDUSTRY_NODE) {
				connectionType = INDUSTRY_TO_INDUSTRY;
			} else {
				connectionType = INDUSTRY_TO_TOWN;
			}
		}
		else {
			if(travelFromNode == travelToNode) {
				connectionType = TOWN_TO_SELF;	
			}
			else{
				connectionType = TOWN_TO_TOWN;
			}
		}
		vehicleGroupID = -1;
	}
	
	function LoadData(data) {
		pathInfo = PathInfo(null, null, null, null);
		vehicleTypes = data["vehicleTypes"];
		pathInfo.LoadData(data["pathInfo"], vehicleTypes);
		vehicleGroupID = data["vehicleGroupID"];
		
		UpdateAfterBuild(vehicleTypes, pathInfo.roadList[pathInfo.roadList.len() - 1].tile, pathInfo.roadList[0].tile, AIStation.GetCoverageRadius(AIStation.GetStationID(pathInfo.roadList[0].tile)));
	}
	
	function SaveData() {
		local saveData = {};
		saveData["cargoID"] <- cargoID;
		saveData["travelFromNode"] <- travelFromNode.GetUID(cargoID);
		saveData["travelToNode"] <- travelToNode.GetUID(cargoID);
		saveData["vehicleTypes"] <- vehicleTypes;
		saveData["pathInfo"] <- pathInfo.SaveData();
		saveData["vehicleGroupID"] <- vehicleGroupID;
		return saveData;
	}
	
	function NewEngineAvailable(engineID) {
		if (AIEngine.GetVehicleType(engineID) != vehicleTypes)
			return;
		local saveBestTransportEngine = bestTransportEngine;
		local saveBestHoldingEngine = bestHoldingEngine;
		bestTransportEngine = null; // To make it possible to re evaluate.
		local bestEngines = GetBestTransportingEngine(vehicleTypes);
		if ((bestEngines != null) && (bestEngines[0] != null) && (bestEngines[1] != null)) {
			if (saveBestTransportEngine == null) {
				// Rare condition that seems to happen once in a while. Don't crash but report the problem.
				Log.logError("bestTransportEngine is null! Connection: " + ToString());
			}
			else {
				if (saveBestTransportEngine == bestEngines[0] || AIEngine.GetDesignDate(bestEngines[0]) < AIEngine.GetDesignDate(saveBestTransportEngine)) {
					bestTransportEngine = saveBestTransportEngine;
					bestHoldingEngine = saveBestHoldingEngine;
					return; // best engine is current engine, no need to replace
				}
				/// @todo We may be replacing too many vehicles all at once costing us a lot of money, We should spread it out over time!
				ManageVehiclesAction.AutoReplaceVehicles(vehicleGroupID, vehicleTypes, bestEngines[0], bestEngines[1]);
				if (AIGameSettings.GetValue("difficulty.vehicle_breakdowns") == 0) {
					// If breakdowns are off vehicles may not go to depots on their own thus no replacement. So tell them to go for maintenance explicitly.
					// Since there is no AI command to send all vehicles in a group for maintenance we have to do it ourselves.
					ManageVehiclesAction.SendVehiclesForMaintenance(vehicleGroupID, vehicleTypes);
				}
				
				//AISign.BuildSign(travelFromNode.GetLocation(), "Replace " + AIEngine.GetName(bestTransportEngine) + " with " + AIEngine.GetName(bestEngines[0]));
			}
			
			bestTransportEngine = bestEngines[0];
			bestHoldingEngine = bestEngines[1];
		}
		else {
			bestTransportEngine = saveBestTransportEngine;
			bestHoldingEngine = saveBestHoldingEngine;
		}
	}
	
	/**
	 * Generate a report which details how many vehicles must be build of what time and how much the connection
	 * (if not already built) is going to cost. If the connection has already been built, it will take into account
	 * the amount of cargo already transported when generating a report detailing how many more vehicles should be built.
	 * @param world The world.
	 * @vehicleType The type of vehicle to use for this connection.
	 * @return A Report instance.
	 */
	function CompileReport(vehicleType) {
		
		//Log.logDebug("Compile Report, now first get best transporting engine");
		local bestEngines = GetBestTransportingEngine(vehicleType);
		
		if (bestEngines == null) {
			//Log.logWarning("No suitable engines found!");
			return null;
		}
		
		local transportingEngineID = bestEngines[0];
		local holdingEngineID = bestEngines[1];
		
		if (vehicleType == this.vehicleTypes && pathInfo != null && pathInfo.build) {
			// If the current best engines are not buildable anymore then update the cached best engines
			if (bestTransportEngine != null && !AIEngine.IsBuildable(bestTransportEngine))
				bestTransportEngine = transportingEngineID;
			if (bestHoldingEngine != null && !AIEngine.IsBuildable(bestHoldingEngine))
				bestHoldingEngine = holdingEngineID;
		}


		// First we check how much we already transport.
		// Check if we already have vehicles who transport this cargo and deduce it from 
		// the number of vehicles we need to build.
		local cargoAlreadyTransported = 0;
		foreach (connection in travelFromNode.connections) {
			if (connection.cargoID == cargoID) {
				
				if (AIGroup.IsValidGroup(vehicleGroupID)) {
					local vehicles = AIVehicleList_Group(vehicleGroupID);
					foreach (vehicle, value in vehicles) {
						local engineID = AIVehicle.GetEngineType(vehicle);
						if (!AIEngine.IsBuildable(engineID))
							continue;
						local travelTime = pathInfo.GetTravelTime(engineID, true) +  pathInfo.GetTravelTime(engineID, false);
						cargoAlreadyTransported += (Date.DAYS_PER_MONTH / travelTime) * AIVehicle.GetCapacity(vehicle, cargoID);
					}
				}
			}
		}	
		
		//return Report(world, travelFromNode, travelToNode, cargoID, transportingEngineID, holdingEngineID, cargoAlreadyTransported);
		return Report(this, transportingEngineID, holdingEngineID, cargoAlreadyTransported);
	}
	
	function GetEstimatedTravelTime(transportEngineID, forward) {
		// If the road list is known we will simulate the engine and get a better estimate.
		// But only if the path roadList is for the same vehicle type as the engine.
		if (pathInfo != null && pathInfo.vehicleType == AIEngine.GetVehicleType(transportEngineID) && pathInfo.roadList != null) {
			return pathInfo.GetTravelTime(transportEngineID, forward);
		} else {
			
			local maxSpeed = AIEngine.GetMaxSpeed(transportEngineID);
			
			// If this is not the case we estimate the distance the engine needs to travel.
			if (AIEngine.GetVehicleType(transportEngineID) == AIVehicle.VT_ROAD) {
				local distance = AIMap.DistanceManhattan(travelFromNode.GetLocation(), travelToNode.GetLocation());
				return distance * Tile.straightRoadLength / maxSpeed;
			} else if (AIEngine.GetVehicleType(transportEngineID) == AIVehicle.VT_AIR) {
	
				// For air connections the distance travelled is different (shorter in general)
				// than road vehicles. A part of the tiles are traversed diagonal, we want to
				// capture this so we can make more precise predictions on the income per vehicle.
				local fromLoc = travelFromNode.GetLocation();
				local toLoc = travelToNode.GetLocation();
				local distanceX = AIMap.GetTileX(fromLoc) - AIMap.GetTileX(toLoc);
				local distanceY = AIMap.GetTileY(fromLoc) - AIMap.GetTileY(toLoc);
	
				if (distanceX < 0) distanceX = -distanceX;
				if (distanceY < 0) distanceY = -distanceY;
	
				local diagonalTiles;
				local straightTiles;
	
				if (distanceX < distanceY) {
					diagonalTiles = distanceX;
					straightTiles = distanceY - diagonalTiles;
				} else {
					diagonalTiles = distanceY;
					straightTiles = distanceX - diagonalTiles;
				}
	
				// Take the landing sequence in consideration.
				local realDistance = diagonalTiles * Tile.diagonalRoadLength + (straightTiles + 40) * Tile.straightRoadLength;
	
				return realDistance / maxSpeed;
			} else if (AIEngine.GetVehicleType(transportEngineID) == AIVehicle.VT_WATER) {
				local distance = AIMap.DistanceManhattan(travelFromNode.GetLocation(), travelToNode.GetLocation());
				return distance * Tile.straightRoadLength / maxSpeed;
			} else if (AIEngine.GetVehicleType(transportEngineID) == AIVehicle.VT_RAIL) {
				local distance = AIMap.DistanceManhattan(travelFromNode.GetLocation(), travelToNode.GetLocation());
				return distance * Tile.straightRoadLength / maxSpeed;
			} else {
				// I've seen this once. Maybe happened just at the moment that this engine expired? Unknown vehicle type 255 (= invalid)
				Log.logError("Unknown vehicle type: " + AIEngine.GetVehicleType(transportEngineID) + ", Engine: " + AIEngine.GetName(transportEngineID));
				return 0;
			}
		}
	}
	
	function HasTrainEnoughPower(engineID, cargoID) {
		local trainWeight = AIEngine.GetWeight(engineID) + 5*18; // Assume for now 5 wagons of 18t each.
		local TE = AIEngine.GetMaxTractiveEffort(engineID);
		// Internally OpenTTD works with a unit called "km-ish/h", which is equal to "mph/1.6". The conversion factor from km-ish/h to km/h is 1.00584
		// We also convert from km/h to meter/sec. km --> * 1000; 1 hour / 60 minutes / 60 seconds. [ * 1000 / 3600 = / 36 ]
		local maxSpeed = AIEngine.GetMaxSpeed(engineID).tofloat() * 1.00584 * 1000 / 3600;
		local hPower = AIEngine.GetPower(engineID);
		// Length: we can get that only from a vehicle not an engine.
		// Assume a length of a half tile for now. meaning with TL 3 we can use 5 wagons
		local isFreight = AICargo.IsFreight(cargoID);
		local steepness = AIGameSettings.GetValue("train_slope_steepness"); // 0-10; // %
		local freight_multiplier = AIGameSettings.GetValue("freight_trains");  // 1-255
		local wagonWeight = 2*18; // Weight for 2 wagons
		if (isFreight) {
			// 5 wagons times 10 ton times multiplier. 10 tons is just a rough very low guess, depends per cargo type and how much the wagon can hold
			// When going higher than 10 we have trouble finding train engines that are strong enough with say 5% incline and multiplier 5
			trainWeight += 5 * 20 * freight_multiplier;
			wagonWeight += 2 * 20 * freight_multiplier;
		}
		else {
			trainWeight += 5 * 2;
			wagonWeight += 2 * 2;
		}
	
		// https://wiki.openttd.org/Tractive_Effort (OUTDATED according to https://www.tt-forums.net/viewtopic.php?p=960459#p960459)
		// This seems to be better: https://wiki.openttd.org/Game_mechanics#Trains
		/// @todo The below computations do NOT take into account the new mechanics yet but they will do for now.
		// NOTE: The slope up steepness should only be computed for the wagons that are currently going upslope!
		// We should have at most 2 of 3 tiles on upslope so deduct 2*wagonweight
		local neededTE = (trainWeight.tofloat() * 35 + (trainWeight.tofloat()-wagonWeight.tofloat()) * steepness * 100) / 1000;
		if (neededTE > TE) {
			Log.logDebug("We needed " + neededTE + " but we have only " + TE + " TE.");
			return false;
		}
		// We want a minimum speed up a slope of 10% of max speed.
		local minSpeed = maxSpeed * 0.10;
		local hpNeeded = neededTE.tofloat() * minSpeed * 1.34102209; // KW to hp = * 1.34102209
		if (hpNeeded > hPower) {
			Log.logDebug("We needed " + hpNeeded + " but we have only " + hPower + " hp.");
			return false;
		}
		Log.logDebug("We needed " + neededTE + " and we have  " + TE + " TE. We needed " + hpNeeded + " and we have " + hPower + " hp.");
		return true;
	}
	
	/// @todo WE NEED TO CHECK WHY THE HELICOPTER IS CHOSEN SO OFTEN AS BEST AIRCRAFT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	function GetBestTransportingEngine(vehicleType) {
		assert (vehicleType != AIVehicle.VT_INVALID);

		// Don't check for max buildable vehicles here because we need to be able to find better replacement vehicles even when
		// we can't buy more vehicles because replacing is possible even at max vehicles.
		
		// If the connection is built and the vehicle type inquired is the same as the vehicle type in use by this connection.
		// Engines can expire so we also need to check that they are still buildable.
		if ((vehicleType == this.vehicleTypes) && bestTransportEngine != null && bestHoldingEngine != null &&
			AIEngine.IsBuildable(bestTransportEngine) && AIEngine.IsBuildable(bestHoldingEngine)) {
			Log.logWarning("Keeping current best engine for existing connection " + ToString() + " - " + AIEngine.GetName(bestTransportEngine));
			return [bestTransportEngine, bestHoldingEngine];
		}
		
		// WARNING: the below bestTransportEngine and bestHoldingEngine are LOCAL meaning they don't set the class vars with the same name!
		// The class vars are only set in UpdateAfterBuild and NewEngineAvailable.
		
		local bestTransportEngine = null;
		local bestHoldingEngine = null;
		local bestIncomePerMonth = 0;
		local engineList = AIEngineList(vehicleType);
		
		foreach (engineID, value in engineList) {
			if (!AIEngine.IsValidEngine(engineID) || !AIEngine.IsBuildable(engineID) || AIEngine.IsWagon(engineID)) {
				// I guess engines that become invalid still stay in the AIEngineList so filter them out.
				continue;
			}
			local transportEngineID = engineID;
			
			// If the vehicle type is an aeroplane, the connection is built and the airport is a small one, make sure we only
			// build small airplanes.
			if (vehicleType == AIVehicle.VT_AIR) {
				if (pathInfo.build && (
				    AIAirport.GetAirportType(pathInfo.roadList[0].tile) == AIAirport.AT_SMALL ||
				    AIAirport.GetAirportType(pathInfo.roadList[0].tile) == AIAirport.AT_COMMUTER
				    )) {
				    if (AIEngine.GetPlaneType(transportEngineID) == AIAirport.PT_BIG_PLANE)
				    	continue;
				    }
			}
			else if (vehicleType == AIVehicle.VT_RAIL) {
				if (!HasTrainEnoughPower(engineID, cargoID)) {
					Log.logDebug("Skipping " + AIEngine.GetName(engineID) + " because it doesn't have enough power.");
					continue;
				}
				if (pathInfo.build) {
					// If the connection is already built then make sure we only select engines that
					// can use the current railtype.
					local railTypeOfConnection = AIRail.GetRailType(pathInfo.depot);
					if (railTypeOfConnection == AIRail.RAILTYPE_INVALID)
						continue;
					if (!AIEngine.CanRunOnRail(engineID, railTypeOfConnection) ||
						!AIEngine.HasPowerOnRail(engineID, railTypeOfConnection) ||
						(AIRail.GetMaxSpeed(railTypeOfConnection) < AIRail.GetMaxSpeed(TrainConnectionAdvisor.GetBestRailType(engineID)))) {
						Log.logDebug("Skipping " + AIEngine.GetName(engineID) +
							" because it needs: " + AIRail.GetName(TrainConnectionAdvisor.GetBestRailType(engineID)));
						continue;
					}
				}
			}

//			Log.logWarning("Process the engine: " + AIEngine.GetName(transportEngineID));
			
			// If the engine is a train we need to check for the best wagon it can pull.
			local holdingEngineID = null;
			if (AIEngine.GetVehicleType(transportEngineID) == AIVehicle.VT_RAIL) {
				
				local bestRailType;
				if (pathInfo.build)
					// If the connection is already built then make sure we only select engines that
					// can use the current railtype.
					bestRailType = AIRail.GetRailType(pathInfo.depot);
				else
					bestRailType = TrainConnectionAdvisor.GetBestRailType(engineID);
				
				if (!AIEngine.CanPullCargo(transportEngineID, cargoID))
					continue;
				
				local wagonEngineList = AIEngineList(vehicleType);
				// We don't want wagons to have a max speed that is a lot slower than the engine speed
				// but we should only care about that if wagon_speed_limits is set to true.
				local minimum_wagonSpeed = 0;
				if (AIGameSettings.GetValue("wagon_speed_limits"))
					// 10% slower is acceptable for now
					minimum_wagonSpeed = AIEngine.GetMaxSpeed(transportEngineID) * 0.9;
				foreach (wagonEngineID, value in wagonEngineList) {
					if (!AIEngine.IsWagon(wagonEngineID) || !AIEngine.IsValidEngine(wagonEngineID) || !AIEngine.IsBuildable(wagonEngineID))
						continue;
					
					if (AIEngine.GetCargoType(wagonEngineID) != cargoID && !AIEngine.CanRefitCargo(wagonEngineID, cargoID))
						continue;
					
					if (!AIEngine.CanRunOnRail(wagonEngineID, bestRailType))
						continue;
					
					// Select the wagon with the biggest capacity and a reasonable maximum speed.
					local wagonSpeed = AIEngine.GetMaxSpeed(wagonEngineID);
					if ((wagonSpeed == 0) || (wagonSpeed >= minimum_wagonSpeed))
						if (holdingEngineID == null)
							holdingEngineID = wagonEngineID;
						/// @todo Capacity should also depend on the length of the wagon!
						else if (AIEngine.GetCapacity(wagonEngineID) >= AIEngine.GetCapacity(holdingEngineID))
							holdingEngineID = wagonEngineID;
				}
			} else {
				holdingEngineID = engineID;
				
				if (AIEngine.GetCargoType(holdingEngineID) != cargoID && !AIEngine.CanRefitCargo(holdingEngineID, cargoID))
					continue;
			}
			
			if (holdingEngineID == null)
				continue;
			
			local report = Report(this, transportEngineID, holdingEngineID, 0);
			if (report.isInvalid)
				continue;

			local reported_veh = report.nrVehicles;
			local nettoIncomePerMonth = report.NettoIncomePerMonth();
			if ((nettoIncomePerMonth == 0) && (reported_veh > 0) && (this.bestTransportEngine == null)) {
				// If we need to know the best replacement engine when replacing an old vehicle and
				// we already have the max allowed vehicles we get 0 back from NettoIncomePerMonth
				// In that case compute income for one vehicle regardless of whether it can currently be built.
				Log.logDebug("We need to check income per month for one vehicle!");
				nettoIncomePerMonth = report.NettoIncomePerMonthForOneVehicle();
			}
			if (nettoIncomePerMonth > bestIncomePerMonth) {
//				if (bestTransportEngine != null)
//					Log.logWarning("+ Replace + " + AIEngine.GetName(bestTransportEngine) + "(" + bestIncomePerMonth + ") with " + AIEngine.GetName(transportEngineID) + "(" + nettoIncomePerMonth + ") x " + report.nrVehicles + " for the connection: " + ToString() + ".");
//				else
//					Log.logWarning("+ New engine " + AIEngine.GetName(transportEngineID) + "(" + nettoIncomePerMonth + ") x " + report.nrVehicles + " for the connection: " + ToString() + ".");
				bestIncomePerMonth = nettoIncomePerMonth;
				bestTransportEngine = transportEngineID;
				bestHoldingEngine = holdingEngineID;
			}// else if (bestTransportEngine != null) {
//				Log.logWarning("- The old engine + " + AIEngine.GetName(bestTransportEngine) + "(" + bestIncomePerMonth + ") is better than " + AIEngine.GetName(transportEngineID) + "(" + nettoIncomePerMonth + ") x " + report.nrVehicles + " for the connection: " + ToString() + ".");
//			}
			//else
			//	Log.logDebug("-----Unprofitable: " + nettoIncomePerMonth + " br ipm " + report.brutoIncomePerMonth + " br cpm " + report.brutoCostPerMonth +
			//		" br ipmv " + report.brutoIncomePerMonthPerVehicle + " br cpmv " + report.brutoCostPerMonthPerVehicle +
			//		" ic pv " + report.initialCostPerVehicle);
		}
		
		if (bestTransportEngine != null)
			Log.logDebug("The best engine for the connection: " + ToString() + " is " + AIEngine.GetName(bestTransportEngine) + " holding cargo by: " + AIEngine.GetName(bestHoldingEngine));
//		else
//			Log.logDebug("No suitable engine found!");

		if (bestTransportEngine == null)
			return null;
		return [bestTransportEngine, bestHoldingEngine];
	}
	
	/**
	 * If the connection is build this function is called to update its
	 * internal state.
	 */
	function UpdateAfterBuild(vehicleType, fromTile, toTile, stationCoverageRadius) {
		
		//Log.logDebug("Connection: UpdateAfterBuild");
		if (!AIGroup.IsValidGroup(vehicleGroupID)) {
			vehicleGroupID = AIGroup.CreateGroup(vehicleType);
			AIGroup.SetName(vehicleGroupID, travelFromNode.GetName() + " to " + travelToNode.GetName());
			// Group names have a max length.
			// If you try to set it to something longer the groupname doesn't get changed.
			// However the last characters are not shown in the gui, instead "..." is shown, so use 28 as max
			// Make it also less likely that group name is not unique by adding cargo label to it.
			local fromName = travelFromNode.GetName();
			if (fromName.len() > 10)
				fromName = fromName.slice(0, 10);
			local toName = travelToNode.GetName();
			if (toName.len() > 10)
				toName = toName.slice(0, 10);
			local groupname = AICargo.GetCargoLabel(cargoID) + " " + fromName + " - " + toName;
			local namelen = 29;
			if (groupname.len() < 29)
				namelen = groupname.len();
			while (!AIGroup.SetName(vehicleGroupID, groupname)) {
				// We give up if our preferred groupname is not unique
				if (AIError.GetLastError() == AIError.ERR_NAME_IS_NOT_UNIQUE) {
					Log.logWarning("Can't set preferred group name. It is not unique!");
					break;
				}
				// String should be at least a few characters long so we can recognize what the group is about.
				if (groupname.len() < 10)
					break;
				namelen--;
				groupname = groupname.slice(0, namelen);
			}
			Log.logDebug("Set group name for group " + vehicleGroupID + " for connection " + ToString() + " to " + groupname);
			if (AIGroup.GetName(vehicleGroupID) != groupname)
				Log.logWarning("Failed to set group name, name used instead: " + AIGroup.GetName(vehicleGroupID));
		}
		Log.logDebug("Updating group " + AIGroup.GetName(vehicleGroupID));
		
		pathInfo.UpdateAfterBuild(vehicleType, fromTile, toTile, stationCoverageRadius);
		lastChecked = AIDate.GetCurrentDate();
		vehicleTypes = vehicleType;
		forceReplan = false;
		
		// Cache the best vehicle we can build for this connection.
		local bestEngines = GetBestTransportingEngine(vehicleTypes);
		if (bestEngines != null) {
			if (bestEngines[0] != null)
				bestTransportEngine = bestEngines[0];
			if (bestEngines[1] != null)
				bestHoldingEngine = bestEngines[1];
		}

		// In the case of a bilateral connection we want to make sure that
		// we don't hinder ourselves; Place the stations not too near each
		// other.
		if (bilateralConnection && connectionType == TOWN_TO_TOWN) {
			travelFromNode.AddExcludeTiles(cargoID, fromTile, stationCoverageRadius);
			travelToNode.AddExcludeTiles(cargoID, toTile, stationCoverageRadius);
		}
		
		travelFromNode.activeConnections.push(this);
		travelToNode.reverseActiveConnections.push(this);
		
		connectionManager.ConnectionRealised(this);
	}
	
	/**
	 * Get the number of vehicles operating.
	 */
	function GetNumberOfVehicles() {

		if (!AIGroup.IsValidGroup(vehicleGroupID))
			return 0;
		return AIVehicleList_Group(vehicleGroupID).Count();
	}
	
	/**
	 * Destroy this connection.
	 */
	function Demolish(destroyFrom, destroyTo, destroyDepots) {
		if (!pathInfo.build)
			return;
			//assert(false);
			
		Log.logWarning("Demolishing connection from " + travelFromNode.GetName() + " to " + travelToNode.GetName());
		
		// Sell all vehicles.
		if (AIGroup.IsValidGroup(vehicleGroupID)) {
			
			local allVehiclesInDepot = false;
		
			// Send and wait till all vehicles are in their respective depots.
			while (!allVehiclesInDepot) {
				allVehiclesInDepot = true;
			
				foreach (vehicleId, value in AIVehicleList_Group(vehicleGroupID)) {
					if (!AIVehicle.IsStoppedInDepot(vehicleId)) {
						allVehiclesInDepot = false;
						// Note that with trains it can take a very long time before all of them
						// are finally in depot, spamming this next message until then
						/// @todo Probably it would be better first sending all trains to depot then
						/// @todo once in a while check if they are all in depot and after that start the Demolish.
						//Log.logDebug("Vehicle: " + AIVehicle.GetName(vehicleId) + " is being sent to depot.");
						// Check if the vehicles is actually going to the depot!
						if ((AIOrder.GetOrderFlags(vehicleId, AIOrder.ORDER_CURRENT) & AIOrder.OF_STOP_IN_DEPOT) == 0) {
							if (!AIVehicle.SendVehicleToDepot(vehicleId) && vehicleTypes == AIVehicle.VT_ROAD) {
								AIVehicle.ReverseVehicle(vehicleId);
								AIController.Sleep(5);
								AIVehicle.SendVehicleToDepot(vehicleId);
							}
						}
					}
				}
				if (!allVehiclesInDepot)
					AIController.Sleep(10);
			}
			// Now that all vehicles are stopped sell them.
			local veh_list = AIVehicleList_Group(vehicleGroupID);
			foreach (veh, dummy in veh_list) {
				Log.logDebug("Selling vehicle " + AIVehicle.GetName(veh));
				if (!AIVehicle.SellVehicle(veh))
					Log.logError("Couldn't sell " + AIVehicle.GetName(veh));
			}
			// Remove the group
			AIGroup.DeleteGroup(vehicleGroupID);
		}
		
		if (destroyFrom) {
			if (vehicleTypes == AIVehicle.VT_ROAD) {
				local startTileList = AITileList();
				local startStation = pathInfo.roadList[pathInfo.roadList.len() - 1].tile;
				
				startTileList.AddTile(startStation);
				DemolishStations(startTileList, AIStation.GetName(AIStation.GetStationID(startStation)), AITileList());
			}
			AITile.DemolishTile(pathInfo.roadList[pathInfo.roadList.len() - 1].tile);
		}
		
		if (destroyTo) {
			if (vehicleTypes == AIVehicle.VT_ROAD) {
				local endTileList = AITileList();
				local endStation = pathInfo.roadList[0].tile;
				
				endTileList.AddTile(endStation);
				DemolishStations(endTileList, AIStation.GetName(AIStation.GetStationID(endStation)), AITileList());
			}
			AITile.DemolishTile(pathInfo.roadList[0].tile);
		}
		
		if (destroyDepots) {
			AITile.DemolishTile(pathInfo.depot);
			if (pathInfo.depotOtherEnd)
				AITile.DemolishTile(pathInfo.depotOtherEnd);
		}
		
		for (local i = 0; i < travelFromNode.activeConnections.len(); i++) {
			if (travelFromNode.activeConnections[i] == this) {
				travelFromNode.activeConnections.remove(i);
				break;
			}
		}
		
		for (local i = 0; i < travelToNode.reverseActiveConnections.len(); i++) {
			if (travelToNode.reverseActiveConnections[i] == this) {
				travelToNode.reverseActiveConnections.remove(i);
				break;
			}
		}

		connectionManager.ConnectionDemolished(this);
		
		pathInfo.build = false;
	}
	
	/**
	 * Utility function to destroy all road stations which are related.
	 * @param tileList A list of tiles which must be removed.
	 * @param stationName The name of stations to be removed.
	 * @param excludeList A list of stations already explored.
	 */
	function DemolishStations(tileList, stationName, excludeList) {
		if (tileList.Count() == 0)
			return;
 
 		local newTileList = AITileList();
		foreach (tile, value in tileList) {

			if (excludeList.HasItem(tile))
				continue;
 			local currentStationID = AIStation.GetStationID(tile);
			foreach (surroundingTile in Tile.GetTilesAround(tile, true)) {
				if (excludeList.HasItem(surroundingTile)) continue;
				excludeList.AddTile(surroundingTile);
	
				local stationID = AIStation.GetStationID(surroundingTile);
	
				if (AIStation.IsValidStation(stationID)) {

					// Only explore this possibility if the station has the same name!
					if (AIStation.GetName(stationID) != stationName)
						continue;
					
					while (AITile.IsStationTile(surroundingTile))
						AITile.DemolishTile(surroundingTile);
					
					if (!newTileList.HasItem(surroundingTile))
						newTileList.AddTile(surroundingTile);
				}			
			}
			
			DemolishStations(newTileList, stationName, excludeList);
 		}
	}
	
	
	// Everything below this line is just a toy implementation designed to test :)
	function GetLocationsForNewStation(atStart) {
		if (!pathInfo.build)
			return AIList();
	
		local tileList = AITileList();	
		local excludeList = AITileList();	
		local tile = null;
		if (atStart) {
			tile = pathInfo.roadList[0].tile;
		} else {
			tile = pathInfo.roadList[pathInfo.roadList.len() - 1].tile;
		}
		excludeList.AddTile(tile);
		GetSurroundingTiles(tile, tileList, excludeList);
		
		return tileList;
	}
	
	function GetSurroundingTiles(tile, tileList, excludeList) {

		local currentStationID = AIStation.GetStationID(tile);
		foreach (surroundingTile in Tile.GetTilesAround(tile, true)) {
			if (excludeList.HasItem(surroundingTile)) continue;

			local stationID = AIStation.GetStationID(surroundingTile);

			if (AIStation.IsValidStation(stationID)) {
				excludeList.AddTile(surroundingTile);

				// Only explore this possibility if the station has the same name!
				if (AIStation.GetName(stationID) != AIStation.GetName(currentStationID))
					continue;

				GetSurroundingTiles(surroundingTile, tileList, excludeList);
				continue;
			}

			if (!tileList.HasItem(surroundingTile))
				tileList.AddTile(surroundingTile);
		}
	}
	
	function GetUID() {
		return travelFromNode.GetUID(cargoID);
	}
	
	function ToString() {
		return "From: " + travelFromNode.GetName() + " to " + travelToNode.GetName() + " carrying: " + AICargo.GetCargoLabel(cargoID);
	}
}
