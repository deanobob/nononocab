/**
 * Industry node which contains all information about an industry and its connections
 * to other industries.
 */
class IndustryConnectionNode extends ConnectionNode
{

	constructor(id) {
		ConnectionNode.constructor(INDUSTRY_NODE, id);
	}
	
	/**
	 * Get the location of this node.
	 * @return The tile location of this node.
	 */
	function GetLocation() {
		return AIIndustry.GetLocation(id);
	}
	
	function GetProducingTiles(cargoID) {
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
		return AITileList_IndustryProducing(id, radius);
	}
	
	function GetAcceptingTiles(cargoID) {
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);
		return AITileList_IndustryAccepting(id, radius);
	}
	
	function GetName() {
		return AIIndustry.GetName(id);
	}
	
	function GetProduction(cargoID) {
		return AIIndustry.GetLastMonthProduction(id, cargoID);
	}
}
