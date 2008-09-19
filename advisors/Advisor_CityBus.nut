class CityBusAdvisor extends Advisor {}

/**
 * Get citybus reports.
 *
 * for each interesting city:
 * - build two stations
 * - build an depot
 * - build n busses (2,3,4)
 * - add route to busses 
 *
 * TODO: Aslo implement N-S.
 * NOTE: At the moment only give an adivse if 4 busses can be build.
 */
function CityBusAdvisor::getReports()
{
	local MINIMUM_BUS_COUNT = 3;
	local MAXIMUM_BUS_COUNT = 5;
	local MINIMUM_DISTANCE = 9;
	local RENDAMENT_OF_CITY = 0.6;
	// AICargo.CC_PASSENGERS = 1 but should be AICargo.CC_COVERED
	local AICargo_CC_PASSENGERS = AICargo.CC_COVERED;
	local CARGO_ID_PASS = 0;
	
	// First is bus.
	local engine_id = innerWorld.cargoTransportEngineIds[0];
	local CityBusCapacity = AIEngine.GetCapacity(engine_id);
	
	local reports = [];
	local options = 0;
	local busses = 0;
	
	// Stations
	local stationE = null;
	local stationW = null;
	//local stationN = null;
	//local stationS = null;
	
	// Reports
	local reportEW = null;
	//local reportNS = null;
	
	// report helpers
	local path_info = null;
	local connection = null;
	local town_node = null;
	local build_action = null;
	local drive_action = null;
	local distance = 0;
	local city_capicity = 0;
	
	foreach(town_node in innerWorld.townConnectionNodes)
	{
		connection = town_node.GetConnection(town_node, CARGO_ID_PASS);
		if(connection == null)
		{
			city_capicity = town_node.GetProduction(AICargo_CC_PASSENGERS) * RENDAMENT_OF_CITY;
			if(city_capicity >= CityBusCapacity * MINIMUM_BUS_COUNT)
			{
				// Search for spots.
				stationE = FindStationTile(town_node, 0);
		 		stationW = FindStationTile(town_node, 2);
				//stationN = FindStationTile(town_node.id, 1);
				//stationS = FindStationTile(town_node.id, 3);
			
				if(AIMap.IsValidTile(stationE) && AIMap.IsValidTile(stationW))
				{
					local distance = AIMap.DistanceManhattan(stationE, stationW);
					if(distance >= MINIMUM_DISTANCE)
					{
						path_info = GetPathInfo(TileAsAIList(stationE),TileAsAIList(stationW));
						
						if(path_info != null)
						{
							busses = city_capicity / CityBusCapacity;
							if(busses > MAXIMUM_BUS_COUNT){ busses = MAXIMUM_BUS_COUNT; }
							
							connection = Connection(CARGO_ID_PASS, town_node, town_node, path_info, true);
							town_node.AddConnection(town_node, connection);
							build_action = BuildRoadAction(connection, true, true);
							drive_action = ManageVehiclesAction();
							drive_action.BuyVehicles(engine_id, busses, connection);
							
							local rpf = RoadPathFinding()
							local cost = busses * AIEngine.GetPrice(engine_id) + rpf.GetCostForRoad(connection.pathInfo.roadList);
							local time = rpf.GetTime(path_info.roadList, AIEngine.GetMaxSpeed(engine_id), true) + Advisor.LOAD_UNLOAD_PENALTY_IN_DAYS;
							local income = AICargo.GetCargoIncome(CARGO_ID_PASS, distance, time);
							local profit = busses * CityBusCapacity * income * (World.DAYS_PER_MONTH / time) - 
											AIEngine.GetRunningCost(engine_id) / World.MONTHS_PER_YEAR;
							local desc = "Build citybus in " + town_node.GetName() + ".";
							reportEW = Report(desc, cost, profit, [build_action, drive_action]);
							//Log.logDebug("Cost: " + cost + ", time: " + time + ", dist: " + distance + ", income: " + income + ", util: " + reportEW.Utility());
							reports.push(reportEW);
						}
					}
				}
			}
		}
		// Update connection.
		else {
		}
	}
	return reports;
}
/**
 * Take the city tile and go to the given direction.
 * While you've got city influence and you're not able to build go further.
 *      (1)
 *       N
 * (2) W + E (0)
 *       S
 *      (3)
 */
function CityBusAdvisor::FindStationTile(/*TownConnectionNode*/ town_node, /*int32*/ direction)
{
	local tile = town_node.GetLocation();
	local x = AIMap.GetTileX(tile);
	local y = AIMap.GetTileY(tile);

	while(AITile.IsWithinTownInfluence(tile, town_node.id)) {
		switch(direction) {
			case 0: x = x - 1; break;
			case 1: y = y - 1; break;
			case 2: x = x + 1; break;
			case 3: y = y + 1; break;
			default: Log.logError("Invalid direction: " + direction); return null;
		}
		tile = AIMap.GetTileIndex(x, y);

		if(IsValidStationTile(tile)) {
			return tile; 
		} 
	}
	// INVALID_TILE
	return -1;
}
function CityBusAdvisor::GetPathInfo(/* AIList */ station0, /* AIList */ station1)
{
	local rpf = RoadPathFinding();
	return rpf.FindFastestRoad(station0, station1, true, true);
}
/**
 *
 */
function CityBusAdvisor::IsValidStationTile(tile)
{
	// Should be buildable
	if(!AITile.IsBuildable(tile) ||
		// No Water 
		AITile.IsWaterTile(tile) ||
		// No road 
		AIRoad.IsRoadTile(tile) ||
		// No station
		AIRoad.IsRoadStationTile(tile) ||
		// No road
		AIRoad.IsRoadDepotTile(tile) ||
		// No onwer or NoCAB is owner
		(AITile.GetOwner(tile) != AICompany.INVALID_COMPANY && AITile.GetOwner(tile) != AICompany.MY_COMPANY)
		){ return false; }
	return true;
}
function CityBusAdvisor::TileAsAIList(/* tile */ tile)
{
	local list = AIList();
	list.AddItem(tile, tile);
	return list;
}