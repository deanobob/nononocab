/**
 * Handle all new road connections.
 */
class TrainConnectionAdvisor extends ConnectionAdvisor {
	
	pathFinder = null;
	allowTownToTownConnections = null;

	constructor(world, connectionManager, allowTownToTown) {
		ConnectionAdvisor.constructor(world, AIVehicle.VT_RAIL, connectionManager);
		allowTownToTownConnections = allowTownToTown;
		local pathFindingHelper = RailPathFinderHelper();
		pathFindingHelper.updateClosedList = false;
		pathFinder = RoadPathFinding(pathFindingHelper);
	}
}

function TrainConnectionAdvisor::GetBuildAction(connection) {
	return BuildRailAction(connection, true, true, world);
}

/**
 * Calculate the path to realise a connection between the nodes in the report.
 */
function TrainConnectionAdvisor::GetPathInfo(report) {

	// Don't do towns! Takes to long for the pathfinder sometimes...	
	if (report.fromConnectionNode.nodeType == ConnectionNode.TOWN_NODE && !allowTownToTownConnections)
		return null;
	local stationType = AIStation.STATION_TRAIN; 
	local stationRadius = AIStation.GetCoverageRadius(stationType);

	local pathInfo = pathFinder.FindFastestRoad(report.fromConnectionNode.GetAllProducingTiles(report.cargoID, stationRadius, 1, 1), report.toConnectionNode.GetAllAcceptingTiles(report.cargoID, stationRadius, 1, 1), true, true, stationType, AIMap.DistanceManhattan(report.fromConnectionNode.GetLocation(), report.toConnectionNode.GetLocation()) * 1.2 + 20, null);
	if (pathInfo == null)
		Log.logDebug("No path found from " + report.fromConnectionNode.GetName() + " to " + report.toConnectionNode.GetName() + " Cargo: " + AICargo.GetCargoLabel(report.cargoID));
	Log.logDebug("Path found!");
	return pathInfo;
}
