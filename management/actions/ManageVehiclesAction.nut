class ManageVehiclesAction extends Action {

	vehiclesToSell = null;		// List of vehicles IDs which need to be sold.
	vehiclesToBuy = null;		// List of [engine IDs, number of vehicles to buy, tile ID of a depot]
	pathfinder = null;

	constructor() { 
		vehiclesToSell = [];
		vehiclesToBuy = [];
		Action.constructor();

		local pathFinderHelper = RoadPathFinderHelper(false);
		pathFinderHelper.costTillEnd = pathFinderHelper.costForNewRoad;

		pathfinder = RoadPathFinding(pathFinderHelper);
	}
}

/**
 * Sell a vehicle when this action is executed.
 * @param vehicleID The vehicle ID of the vehicle which needs to be sold.
 */
function ManageVehiclesAction::SellVehicles(engineID, number, connection)
{
	vehiclesToSell.push([engineID, number, connection]);
}

/**
 * Buy a certain number of vehicles when this action is executed.
 * @param engineID The engine ID of the vehicles which need to be build.
 * @param number The number of vehicles to build.
 * @param connection The connection where the vehicles are to operate on.
 */
function ManageVehiclesAction::BuyVehicles(engineID, number, wagonEngineID, numberWagons, connection)
{
	vehiclesToBuy.push([engineID, number, wagonEngineID, numberWagons, connection]);
}

function ManageVehiclesAction::Execute()
{
	AIExecMode();
	// Sell the vehicles.
	//Log.logInfo("Sell " + vehiclesToSell.len() + " vehicles.");
	foreach (engineInfo in vehiclesToSell) {
		local engineID = engineInfo[0];
		local vehicleNumbers = engineInfo[1];
		local connection = engineInfo[2];
		local vehicleType = AIEngine.GetVehicleType(engineID);
		
		pathfinder.pathFinderHelper.SetStationBuilder(AIEngine.IsArticulated(engineID));
		
		// First of all we need to find suitable candidates to remove.
		local vehicleList = AIList();
		local vehicleArray = null;

		local vehicleList = AIVehicleList_Group(connection.vehicleGroupID);
		vehicleList.Valuate(AIVehicle.GetAge);
		vehicleList.Sort(AIList.SORT_BY_VALUE, true);
		vehicleList.Valuate(AIVehicle.GetEngineType);
		vehicleList.KeepValue(engineID);
		if (!connection.bilateralConnection) {
			vehicleList.Valuate(AIVehicle.GetCargoLoad, AIEngine.GetCargoType(engineID));
			vehicleList.RemoveAboveValue(0);
		}

		local vehiclesDeleted = 0;
		
		foreach (vehicleID, value in vehicleList) {
			Log.logDebug("Vehicle: " + AIVehicle.GetName(vehicleID) + " is being sent to depot to be sold.");
			
			// Take a different approach with ships, as they might get lost.
			if (vehicleType == AIVehicle.VT_WATER) {
				AIOrder.SetOrderCompareValue(vehicleID, 0, 0);
				++vehiclesDeleted;
			} else if (!AIVehicle.SendVehicleToDepot(vehicleID)) {
        		AIVehicle.ReverseVehicle(vehicleID);
				AIController.Sleep(5);
				if (AIVehicle.SendVehicleToDepot(vehicleID))
					++vehiclesDeleted;
			}
			else
				++vehiclesDeleted;

			if (vehiclesDeleted == vehicleNumbers/* && AIEngine.GetVehicleType(engineID) == AIVehicle.VT_AIR*/) {
				// Update the creation date of the connection so vehicles don't get
				// removed twice!
				connection.pathInfo.buildDate = AIDate.GetCurrentDate();
				break;
			}
		}
	}
	
	// Buy the vehicles.
	// During execution we keep track of the number of vehicles we can buy.
	foreach (engineInfo in vehiclesToBuy) {
		local engineID = engineInfo[0];
		local vehicleNumbers = engineInfo[1];
		local wagonEngineID = engineInfo[2];
		local numberWagons = engineInfo[3];
		local connection = engineInfo[4];

		local vehicleID = null;
		local vehicleGroup = null;
		local vehicleType = AIEngine.GetVehicleType(engineID);
		
		if (vehicleType == AIVehicle.VT_RAIL) {
			// Extra check to make sure we can build engine in current depot even though incompatibility should not happen here.
			local railTypeOfConnection = AIRail.GetRailType(connection.pathInfo.depot);
			if (!AIEngine.CanRunOnRail(engineID, railTypeOfConnection) ||
				!AIEngine.HasPowerOnRail(engineID, railTypeOfConnection) ||
				(AIRail.GetMaxSpeed(railTypeOfConnection) < AIRail.GetMaxSpeed(TrainConnectionAdvisor.GetBestRailType(engineID)))) {
				// This shouldn't happen anymore.
				Log.logError("Unexpectedly we can't use the chosen rail engine on the current track!");
				Log.logWarning("Railtype: " + AIRail.GetName(railTypeOfConnection) + ", but engine: " + AIEngine.GetName(engineID) +
					" needs: " + AIRail.GetName(TrainConnectionAdvisor.GetBestRailType(engineID)));
				continue;
			}
		}

		local maxBuildableVehicles =  GameSettings.GetMaxBuildableVehicles(vehicleType);
		if (vehicleNumbers > maxBuildableVehicles)
			vehicleNumbers = maxBuildableVehicles;
		
		if (vehicleNumbers == 0) {
			Log.logInfo("Can't buy more vehicles, we have reached the maximum!");
			continue; /// @todo Maybe we should even use a break here since we can't get more vehicles.
		}
		Log.logInfo("Buy " + vehicleNumbers + " " + AIEngine.GetName(engineID) + " " + AIEngine.GetName(wagonEngineID) + ".");

		// Search if there are already have a vehicle group for this connection.
		assert (AIGroup.IsValidGroup(connection.vehicleGroupID));
/*		if (!AIGroup.IsValidGroup(connection.vehicleGroupID)) {
			connection.vehicleGroupID = AIGroup.CreateGroup(AIEngine.GetVehicleType(engineID));
			AIGroup.SetName(connection.vehicleGroupID, connection.travelFromNode.GetName() + " to " + connection.travelToNode.GetName());
		}*/
		
		// In case of a bilateral connection we want to spread the load by sending the trucks
		// in opposite directions.
		local directionToggle = AIStation.GetCargoWaiting(connection.pathInfo.travelFromNodeStationID, connection.cargoID) 
			> AIStation.GetCargoWaiting(connection.pathInfo.travelToNodeStationID, connection.cargoID);
		
		// Use a 'main' vehicle to enable the sharing of orders.
		local roadList = connection.pathInfo.roadList;

		// If we want to build aircrafts or ships, we only want to build 1 per station!
		if (AIEngine.GetVehicleType(engineID) == AIVehicle.VT_WATER || AIEngine.GetVehicleType(engineID) == AIVehicle.VT_AIR) {
			if (connection.bilateralConnection && vehicleNumbers > 4)
				vehicleNumbers = 4;
			else if (vehicleNumbers > 2)
				vehicleNumbers = 2;
		} else if (AIEngine.GetVehicleType(engineID) == AIVehicle.VT_ROAD) {
			if (connection.bilateralConnection && vehicleNumbers > 30)
				vehicleNumbers = 30;
			else if (vehicleNumbers > 15)
				vehicleNumbers = 15;
		}
			
		local vehiclePrice = AIEngine.GetPrice(engineID);
		if (AIEngine.GetVehicleType(engineID) == AIVehicle.VT_RAIL)
			vehiclePrice += numberWagons * AIEngine.GetPrice(wagonEngineID);
		totalCosts = vehiclePrice;

		local vehicleCloneID = -1;
		local vehicleCloneIDReverse = -1;
		for (local i = 0; i < vehicleNumbers; i++) {
		
			if (Finance.GetMaxMoneyToSpend() - vehiclePrice < 0) {
				Log.logDebug("Not enough money to build all prescibed vehicles!");
				break;
			}
					
			local vehicleID;

			if (!directionToggle && connection.bilateralConnection) {
				if (vehicleCloneIDReverse != -1) {
					vehicleID = AIVehicle.CloneVehicle(connection.pathInfo.depotOtherEnd, vehicleCloneIDReverse, false);
					directionToggle = !directionToggle;
					AIGroup.MoveVehicle(connection.vehicleGroupID, vehicleID);
					AIVehicle.StartStopVehicle(vehicleID);
					continue;
				}
				vehicleID = AIVehicle.BuildVehicle(connection.pathInfo.depotOtherEnd, engineID);
				vehicleCloneIDReverse = vehicleID;
			} else {
				if (vehicleCloneID != -1) {
					vehicleID = AIVehicle.CloneVehicle(connection.pathInfo.depot, vehicleCloneID, false);
					directionToggle = !directionToggle;
					AIGroup.MoveVehicle(connection.vehicleGroupID, vehicleID);
					AIVehicle.StartStopVehicle(vehicleID);
					continue;
				}
				vehicleID = AIVehicle.BuildVehicle(connection.pathInfo.depot, engineID);
				vehicleCloneID = vehicleID;
			}
			if (!AIVehicle.IsValidVehicle(vehicleID)) {
				Log.logError("Error building vehicle: " + AIError.GetLastErrorString() + connection.pathInfo.depotOtherEnd + "!");
				continue;
			}

			// Refit if necessary.
			if (connection.cargoID != AIEngine.GetCargoType(engineID))
				AIVehicle.RefitVehicle(vehicleID, connection.cargoID);
			//vehicleGroup.vehicleIDs.push(vehicleID);
			AIGroup.MoveVehicle(connection.vehicleGroupID, vehicleID);

			// In the case of a train, also build the wagons, make sure that we cut on the wagons
			// if the train is bigger than 1 tile.
			// TODO: Make sure to make this also works for cloned vehicles.
			if (AIEngine.GetVehicleType(engineID) == AIVehicle.VT_RAIL) {
				local nrWagons = numberWagons - (AIVehicle.GetLength(vehicleID) / 8) + 1;
				for (local j = 0; j < nrWagons; j++) {
					local wagonVehicleID = AIVehicle.BuildVehicle((!directionToggle && connection.bilateralConnection ? connection.pathInfo.depotOtherEnd : connection.pathInfo.depot), wagonEngineID);
				
					if (!AIVehicle.IsValidVehicle(wagonVehicleID)) {
						Log.logError("Error building vehicle: " + AIError.GetLastErrorString() + " " + connection.pathInfo.depot + "!");
						continue;
					}

					if (connection.cargoID != AIEngine.GetCargoType(wagonVehicleID))
						AIVehicle.RefitVehicle(wagonVehicleID, connection.cargoID);
				
					AIVehicle.MoveWagon(wagonVehicleID, 0, vehicleID, 0);
				}
			}

			SetOrders(vehicleID, vehicleType, connection, directionToggle);

			AIVehicle.StartStopVehicle(vehicleID);

			// Update the game setting so subsequent actions won't build more vehicles then possible!
			// (this will be overwritten anyway during the update).
			GameSettings.maxVehiclesBuildLimit[vehicleType]--;

			directionToggle = !directionToggle;
		}			
	}
	CallActionHandlers();
	return true;
}

/**
 * Set orders for vehicle.
 * @param vehicleID The ID of the vehicle to assign orders to.
 * @param vehicleType The type of vehicle.
 * @param connection The connection this vehicle belongs to.
 * @param directionToggle Whether or not to reverse the to and from stations in orders.
 * @pre Valid vehicle, connection, connection.pathInfo, connection.pathInfo.roadList.
 */
function ManageVehiclesAction::SetOrders(vehicleID, vehicleType, connection, directionToggle)
{
	local extraOrderFlags = (vehicleType == AIVehicle.VT_RAIL || vehicleType == AIVehicle.VT_ROAD ? AIOrder.OF_NON_STOP_INTERMEDIATE : 0);
	local roadList = connection.pathInfo.roadList;
	
	// Send the vehicles on their way.
	if (connection.bilateralConnection && !directionToggle) {
		if (vehicleType == AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depotOtherEnd, AIOrder.OF_NONE | extraOrderFlags);
		AIOrder.AppendOrder(vehicleID, roadList[0].tile, AIOrder.OF_FULL_LOAD_ANY | extraOrderFlags);
		if (vehicleType != AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depotOtherEnd, AIOrder.OF_NONE | extraOrderFlags);

		// If it's a ship, give it additional orders!
		if (vehicleType == AIVehicle.VT_WATER)
			for (local i = 1; i < roadList.len() - 1; i++)
				AIOrder.AppendOrder(vehicleID, roadList[i].tile, AIOrder.OF_NONE | extraOrderFlags);

		if (vehicleType == AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depot, AIOrder.OF_NONE | extraOrderFlags);
		AIOrder.AppendOrder(vehicleID, roadList[roadList.len() - 1].tile, AIOrder.OF_FULL_LOAD_ANY | extraOrderFlags);

		if (vehicleType != AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depot, AIOrder.OF_NONE | extraOrderFlags);

		if (vehicleType == AIVehicle.VT_WATER) 
			for (local i = roadList.len() - 2; i > 0; i--)
				AIOrder.AppendOrder(vehicleID, roadList[i].tile, AIOrder.OF_NONE | extraOrderFlags);
	} else {
		if (vehicleType == AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depot, AIOrder.OF_NONE | extraOrderFlags);
		AIOrder.AppendOrder(vehicleID, roadList[roadList.len() - 1].tile, AIOrder.OF_FULL_LOAD_ANY | extraOrderFlags);
		if (vehicleType != AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depot, AIOrder.OF_NONE | extraOrderFlags);

		// If it's a ship, give it additional orders!
		if (vehicleType == AIVehicle.VT_WATER) {
			for (local i = roadList.len() - 2; i > 0; i--) {
				if (!AIMarine.IsBuoyTile(roadList[i].tile)) {
					AISign.BuildSign(roadList[i].tile, "NO BUOY!?");
					assert (false);
				}
				AIOrder.AppendOrder(vehicleID, roadList[i].tile, AIOrder.OF_NONE | extraOrderFlags);
			}
		}

		if (vehicleType == AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depotOtherEnd, AIOrder.OF_NONE | extraOrderFlags);

		if (connection.bilateralConnection)
			AIOrder.AppendOrder(vehicleID, roadList[0].tile, AIOrder.OF_FULL_LOAD_ANY | extraOrderFlags);
		else
			AIOrder.AppendOrder(vehicleID, roadList[0].tile, AIOrder.OF_UNLOAD | AIOrder.OF_NO_LOAD);

		if (connection.bilateralConnection && vehicleType != AIVehicle.VT_RAIL)
			AIOrder.AppendOrder(vehicleID, connection.pathInfo.depotOtherEnd, AIOrder.OF_NONE | extraOrderFlags);
			
		if (vehicleType == AIVehicle.VT_WATER)
			for (local i = 1; i < roadList.len() - 1; i++)
				AIOrder.AppendOrder(vehicleID, roadList[i].tile, AIOrder.OF_NONE | extraOrderFlags);
	}

	// As a first order, let the vehicle do it's normal actions when not old enough.
	AIOrder.InsertConditionalOrder(vehicleID, 0, 0);
	
	// Set orders to stop the vehicle in a depot once it reached its max age.
	AIOrder.SetOrderCondition(vehicleID, 0, AIOrder.OC_AGE);
	AIOrder.SetOrderCompareFunction(vehicleID, 0, AIOrder.CF_LESS_THAN);
	AIOrder.SetOrderCompareValue(vehicleID, 0, AIVehicle.GetMaxAge(vehicleID) / 366);
	
	// Insert the stopping order, which will be skipped by the previous conditional order
	// if the vehicle hasn't reached its maximum age.
	if (connection.bilateralConnection && directionToggle)
		AIOrder.InsertOrder(vehicleID, 1, connection.pathInfo.depotOtherEnd, AIOrder.OF_STOP_IN_DEPOT);
	else
		AIOrder.InsertOrder(vehicleID, 1, connection.pathInfo.depot, AIOrder.OF_STOP_IN_DEPOT);
}
