pragma solidity ^0.4.25;

import "./Permission.sol";
import "./SafeMath.sol";

import "./IERC20.sol";
import "./IRoundCalendar.sol";


contract RandomDataSource is Permission{
   using SafeMath for uint;
   event RandomIndexed(uint256 source, uint256 index);

    function ROUND_RANDOM_SEED(uint256 _roundId)  public view returns (uint256) {
        return uintStorage[keccak256(abi.encodePacked("ROUND_RANDOM_SEED", _roundId))];
    }

    function SAVE_ROUND_RANDOM_SEED(uint256 _roundId, uint256 _seed) internal {
        uintStorage[keccak256(abi.encodePacked("ROUND_RANDOM_SEED", _roundId))] = _seed;
    }

    function SET_ROUND_CALENDAR(address _new) onlyOwner public  {
        addressStorage[keccak256("ROUND_CALENDAR")] = _new;
    }

    function ROUND_CALENDAR() public view returns (address) {
        return addressStorage[keccak256("ROUND_CALENDAR")];
    }

    function initialized() public view returns (bool) {
        return boolStorage[keccak256("initialized")];
    }

   function roundIndexCountKey(uint256 _roundId) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("roundIndexCountKey", _roundId));
   }

   function roundIndexKey(uint256 _roundId, uint256 _index) internal pure returns(bytes32){
      return keccak256(abi.encodePacked("roundIndexKey", _roundId, _index));
   }

  function initialize(  
        address _owner, 
        address _roundCalendar) public{
        require(!initialized());
        setOwner(_owner);
        SET_ROUND_CALENDAR(_roundCalendar);
        boolStorage[keccak256("initialized")] = true;
  }

    function isRandomSelected(uint256 _roundId, uint256 _index) public view returns(bool){
        return boolStorage[roundIndexKey(_roundId, _index)];
    }

    function randomIndexCount(uint256 _roundId) public view returns(uint256){
        return uintStorage[roundIndexCountKey(_roundId)];
    }

   function fillRandomData(uint256 _roundId, uint256[] _indexes) public hasAdminRole{
       require(_indexes.length > 0, "No data");
       if(_roundId == 0){
           _roundId = currentRoundId().sub(1);
       }
       uint256 _filledTotal = 0;
       for(uint256 i=0;i<_indexes.length;i++){
           uint256 _index = _indexes[i];
           bytes32 _roundIndexKey = roundIndexKey(_roundId, _index);
           if(!boolStorage[_roundIndexKey]){//prevent duplicated insert
               boolStorage[_roundIndexKey] = true;
               emit RandomIndexed(_roundId, _index);
               _filledTotal++;
           }
       }
       //Update total of the round data
       if(_filledTotal > 0){
           bytes32 _roundIndexCountKey = roundIndexCountKey(_roundId);
           uint256 _total = uintStorage[_roundIndexCountKey];
           _total = _total.add(_filledTotal);
           uintStorage[_roundIndexCountKey] = _total;
       }
       
   }

   function currentRoundId() internal view returns(uint256){
        return RoundCalendar(ROUND_CALENDAR()).CURRENT_ROUND();
    }
   function getRoundSeed(uint256 _roundId) public view returns(uint256){
       if(_roundId == 0){
           _roundId = currentRoundId().sub(1);
       }
       return ROUND_RANDOM_SEED(_roundId);
   }

   function randomSeed() public returns(uint256){
       uint256 _lastRoundId = currentRoundId().sub(1);
       require(_lastRoundId >0);
       require(ROUND_RANDOM_SEED(_lastRoundId) == 0, "Round random seed has been generated");
       uint256 _seed = genRandom();
       SAVE_ROUND_RANDOM_SEED(_lastRoundId, _seed);
       return _seed;
    }

    function randomSeedByAdmin(uint256 _roundId) public hasAdminRole returns(uint256){
       require(_roundId < currentRoundId());
       require(ROUND_RANDOM_SEED(_roundId) == 0, "Round random seed has been generated");
       uint256 _seed = genRandom();
       SAVE_ROUND_RANDOM_SEED(_roundId, _seed);
       return _seed;
    }

    function genRandom() private view returns (uint) {
        return uint256(keccak256(
            abi.encodePacked(
                tx.origin, 
                blockhash(block.number - 1), 
                block.timestamp
        )));
    }
}