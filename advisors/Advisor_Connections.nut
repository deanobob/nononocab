import("queue.binary_heap", "BinaryHeap", 1);

/**
 * Build economy tree with primary economies which require no input
 * to produce on the root level, secundary economies which require
 * input from primary industries as children and so on. The max 
 * depth in OpenTTD is 4;
 *
 * Grain                              }
 * Iron ore        -> Steel           }-> Goods  -> Town
 * Livestock                          }
 */
class ConnectionAdvisor extends Advisor
{
	world = null;				// Pointer to the World class.
	cargoTransportEngineIds = null;		// The fastest engine IDs to transport the cargos.
	connectionReports = null;
	
	industry_tree = null;
	industryCacheAccepting = null;
	industryCacheProducing = null;
	
	constructor(world)
	{
		this.world = world;		
		cargoTransportEngineIds = array(AICargoList().Count(), -1);
		connectionReports = BinaryHeap();
		
		BuildIndustryTree();
		UpdateIndustryConnections();
	}
	
	function BuildIndustryTree();
	function UpdateIndustryConnections();
	function getReports();
	function UpdateCargoTransportEngineIds();
	function PrintTree();
	function PrintNode();
}
	
	
function ConnectionAdvisor::BuildIndustryTree() {
	// Construct complete industry node list.
	local industries = world.industry_list;
	local cargos = AICargoList();
	industryCacheAccepting = array(cargos.Count());
	industryCacheProducing = array(cargos.Count());

	industry_tree = [];

	// Fill the arrays with empty arrays, we can't use:
	// local industryCacheAccepting = array(cargos.Count(), [])
	// because it will all point to the same empty array...
	for (local i = 0; i < cargos.Count(); i++) {
		industryCacheAccepting[i] = [];
		industryCacheProducing[i] = [];
	}

	// For each industry we will determine all possible connections to other
	// industries which accept its goods. We build a tree structure in which
	// the root nodes consist of industry nodes who only produce products but
	// don't accept anything (the so called primary industries). The children
	// of these nodes are indutries which only accept goods which the root nodes
	// produce, and so on.
	//
	// Primary economies -> Secondary economies -> ... -> Towns
	// Town <-> town
	//
	//
	// Every industry is stored in an IndustryNode.
	foreach (industry, value in industries) {

		local industryNode = IndustryNode();
		industryNode.industryID = industry;

		// Check which cargo is accepted.
		foreach (cargo, value in cargos) {

			// Check if the industry actually accepts something.
			if (AIIndustry.IsCargoAccepted(industry, cargo)) {
				industryNode.cargoIdsAccepting.push(cargo);

				// Add to cache.
				industryCacheAccepting[cargo].push(industryNode);

				// Check if there are producing plants which this industry accepts.
				for (local i = 0; i < industryCacheProducing[cargo].len(); i++) {
					industryCacheProducing[cargo][i].industryNodeList.push(industryNode);
				}
			}

			if (AIIndustry.GetProduction(industry, cargo) != -1) {	

				// Save production information.
				industryNode.cargoIdsProducing.push(cargo);
				industryNode.cargoProducing.push(AIIndustry.GetProduction(industry, cargo));

				// Add to cache.
				industryCacheProducing[cargo].push(industryNode);

				// Check for accepting industries for these products.
				for (local i = 0; i < industryCacheAccepting[cargo].len(); i++) {
					industryNode.industryNodeList.push(industryCacheAccepting[cargo][i]);
				}
			}
		}

		// If the industry doesn't accept anything we add it to the root list.
		if (industryNode.cargoIdsAccepting.len() == 0) {
			industry_tree.push(industryNode);
		}
	}
}

function ConnectionAdvisor::UpdateIndustryConnections() {
	UpdateCargoTransportEngineIds();

	// Upon initialisation we look at all possible connections in the world and try to
	// find the most prommising once in terms of cost to build to profit ratio. We can't
	// however get perfect information by calculating all possible routes as that will take
	// us way to much time.
	//
	// Therefore we try to get an indication by taking the Manhattan distance between two
	// industries and see what the profit would be if we would be able to build a straight
	// road and let and vehicle operate on it.
	//
	// The next step would be to look at the most prommising connection nodes and do some
	// actual pathfinding on that selection to find the best one(s).
	foreach (primIndustry in industry_tree) {

		foreach (secondIndustry in primIndustry.industryNodeList) {

			// Check if this connection already exists.
			if (primIndustry.industryConnections.rawin("" + secondIndustry)) {

				// See if we need to add or remove some vehicles.

			} else {
				local manhattanDistance = AIMap.DistanceManhattan(AIIndustry.GetLocation(primIndustry.industryID), 
					AIIndustry.GetLocation(secondIndustry.industryID));

				// Take a guess at the travel time and profit for each cargo type.
				foreach (cargo in primIndustry.cargoIdsProducing) {

					local maxSpeed = AIEngine.GetMaxSpeed(cargoTransportEngineIds[cargo]);
					local travelTime = manhattanDistance * RoadPathFinding.straightRoadLength / maxSpeed;
					local incomePerRun = AICargo.GetCargoIncome(cargo, manhattanDistance, travelTime.tointeger()) * AIEngine.GetCapacity(cargoTransportEngineIds[cargo]);

					local report = ConnectionReport();
					report.profitPerMonthPerVehicle = (30.0 / travelTime) * incomePerRun;
					report.engineID = cargoTransportEngineIds[cargo];
					report.fromIndustryNode = primIndustry;
					report.toIndustryNode = secondIndustry;
					report.cargoID = cargo;

					connectionReports.Insert(report, -report.profitPerMonthPerVehicle);
				}
			}
		}
	}
}

/**
 * Construct a report by finding the largest subset of buildable infrastructure given
 * the amount of money available to us, which in turn yields the largest income.
 */
function ConnectionAdvisor::getReports()
{
	// The actionlist to construct.
	local actionList = [];

	local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);

	// Check how much we have to spend:
	local money = AICompany.GetBankBalance(AICompany.MY_COMPANY);

	// Try to get the best subset of options.
	local report;
	while ((report = connectionReports.Pop()) != null) {

		// If the report is already fully calculated, check if we can afford it and execute it!
		if (report.cost != 0 && report.cost < money) {

			local otherIndustry = report.fromIndustryNode.GetIndustryConnection(report.toIndustryNode.industryID);
			if (otherIndustry != null && otherIndustry.build == true) {
				// Check if we need to add / remove vehicles to this connection.

			} else {
				// The cost has already been calculated, so we can build it immediatly.
				report.print();
				money -= report.cost;
			}
		} else if (report.cost == 0) {

			// If we haven't calculated yet what it cost to build this report, we do it now.
			local pathfinder = RoadPathFinding();
			local pathList = pathfinder.FindFastestRoad(AITileList_IndustryProducing(report.fromIndustryNode.industryID, radius), AITileList_IndustryAccepting(report.toIndustryNode.industryID, radius));

			if (pathList == null) {
				print("No path found from " + AIIndustry.GetName(report.fromIndustryNode.industryID) + " to " + AIIndustry.GetName(report.toIndustryNode.industryID));
				continue;
			}
			// Now we know the prices, check how many vehicles we can build and what the actual income per vehicle is.
			local timeToTravelTo = pathfinder.GetTime(pathList.roadList, AIEngine.GetMaxSpeed(report.engineID), true);
			local timeToTravelFrom = pathfinder.GetTime(pathList.roadList, AIEngine.GetMaxSpeed(report.engineID), false);

			// Calculate bruto income per vehicle per run.
			local incomePerRun = AICargo.GetCargoIncome(report.cargoID, 
				AIMap.DistanceManhattan(pathList.roadList[0].tile, pathList.roadList[pathList.roadList.len() - 1].tile), 
				timeToTravelTo) * AIEngine.GetCapacity(report.engineID);


			// Calculate netto income per vehicle.
			local incomePerVehicle = incomePerRun - ((timeToTravelTo + timeToTravelFrom) * AIEngine.GetRunningCost(report.engineID) / 364);

			local productionPerMonth;
			// Calculate the number of vehicles which can operate:
			for (local i = 0; i < report.fromIndustryNode.cargoIdsProducing.len(); i++) {

				if (report.cargoID == report.fromIndustryNode.cargoIdsProducing[i]) {
					productionPerMonth = report.fromIndustryNode.cargoProducing[i];
					break;
				}
			}

			local transportedCargoPerVehiclePerMonth = (30.0 / (timeToTravelTo + timeToTravelFrom)) * AIEngine.GetCapacity(report.engineID);
			report.nrVehicles = productionPerMonth / transportedCargoPerVehiclePerMonth;

			// Calculate the profit per month per vehicle
			report.profitPerMonthPerVehicle = incomePerVehicle * (30.0 / (timeToTravelTo + timeToTravelFrom));
			report.cost = pathfinder.GetCostForRoad(pathList.roadList) + report.nrVehicles * AIEngine.GetPrice(report.engineID);

			if (report.cost < money) {
				report.Print();
				print("Extra information: Time to travel to: " + timeToTravelTo + ". Time to travel from: " + timeToTravelFrom);
				print("Extra information: incomePerRun: " + incomePerRun + ". Income per vehicle: " + incomePerVehicle);
				money -= report.cost;

				// Check if the industry connection node actually exists else create it.
				local industryConnectionNode = report.fromIndustryNode.GetIndustryConnection(report.toIndustryNode);
				if (!industryConnectionNode) {
					industryConnectionNode = IndustryConnection(report.fromIndustryNode, report.toIndustryNode);
					report.fromIndustryNode.AddIndustryConnection(report.toIndustryNode, industryConnectionNode);
				}

				// Give the action to build the road.
				actionList.push(BuildRoadAction(industryConnectionNode, pathList.roadList, true, true));

				// Add the action to build the vehicles.
				local vehicleAction = ManageVehiclesAction();
				vehicleAction.BuyVehicles(report.engineID, report.nrVehicles, industryConnectionNode);
				actionList.push(vehicleAction);
			}
		}
	}

	return actionList;
}

/**
 * Check all available vehicles to transport all sorts of cargos and save
 * the max speed of the fastest transport for each cargo.
 */
function ConnectionAdvisor::UpdateCargoTransportEngineIds() {

	local cargos = AICargoList();
	local i = 0;
	foreach (cargo, value in cargos) {

		local engineList = AIEngineList(AIVehicle.VEHICLE_ROAD);
		foreach (engine, value in engineList) {
			if (AIEngine.GetCargoType(engine) == cargo&& 
				AIEngine.GetMaxSpeed(cargoTransportEngineIds[i]) < AIEngine.GetMaxSpeed(engine)) {
				cargoTransportEngineIds[i] = engine;
			}
		}
		i++;
	}

	for (local i = 0; i < cargoTransportEngineIds.len(); i++) {
		print("Engines : " + cargoTransportEngineIds[i]);
		print("Capacity : " + AIEngine.GetCapacity(cargoTransportEngineIds[i]));
		print("Cargo : " + AICargo.GetCargoLabel(AIEngine.GetCargoType(cargoTransportEngineIds[i])));
	}
}





/**
 * Debug purposes only.
 */
function ConnectionAdvisor::PrintTree() {
	print("PrintTree");
	foreach (primIndustry in industry_tree) {
		PrintNode(primIndustry, 0);
	}
	print("Done!");
}

function ConnectionAdvisor::PrintNode(node, depth) {
	local string = "";
	for (local i = 0; i < depth; i++) {
		string += "      ";
	}

	print(string + AIIndustry.GetName(node.industryID) + " -> ");

	foreach (transport in node.industryConnections) {
		print("Vehcile travel time: " + transport.timeToTravelTo);
		//print("Vehcile income per run: " + transport.incomePerRun);
		print("Cargo: " + AICargo.GetCargoLabel(transport.cargoID));
		print("Cost: " + node.costToBuild);
	}
	foreach (iNode in node.industryNodeList)
		PrintNode(iNode, depth + 1);
}	

class ConnectionReport {

	profitPerMonthPerVehicle = 0;	// The utility value.
	engineID = 0;			// The vehicles to build.
	nrVehicles = 0;			// The number of vehicles to build.
	roadList = null;		// The road to build.

	fromIndustryNode = null;	// The industry which produces the cargo.
	toIndustryNode = null;		// The industry which accepts the produced cargo.
	
	cargoID = 0;			// The cargo to transport.
	
	cost = 0;			// The cost of this operation.
	
	function Print() {
		print("Build a road from " + AIIndustry.GetName(fromIndustryNode.industryID) + " to " + AIIndustry.GetName(toIndustryNode.industryID) +
		" transporting " + AICargo.GetCargoLabel(cargoID) + " and build " + nrVehicles + " vehicles. Cost: " +
		cost + " income per month per vehicle: " + profitPerMonthPerVehicle);
	}
}


