pragma solidity ^0.4.25;

import "./SafeMath.sol";
import "./Ownable.sol";


contract RoundCalendar is Ownable{
  using SafeMath for uint;
  function initialize(  
        address _owner, 
        uint256 _genesisBlock,
        uint256 _blockPerPeriod
        ) public{
        require(!initialized());
        setOwner(_owner);
        uintStorage[keccak256("BLOCKS_PER_PERIOD")] = _blockPerPeriod;
        uintStorage[keccak256("GENESIS_BLOCK")] = _genesisBlock;
        boolStorage[keccak256("initialized")] = true;
  }
    function initialized() public view returns (bool) {
        return boolStorage[keccak256("initialized")];
    }

    function GENESIS_BLOCK() public view returns (uint256) {
        return uintStorage[keccak256("GENESIS_BLOCK")];
    }
    function BLOCKS_PER_PERIOD() public view returns (uint256) {
        return uintStorage[keccak256("BLOCKS_PER_PERIOD")];
    }
    function SET_BLOCKS_PER_PERIOD(uint256 _blocks) onlyOwner public {
        require(_blocks > 0);
        uintStorage[keccak256("BLOCKS_PER_PERIOD")] = _blocks;
    }

    function SET_GENESIS_BLOCK(uint256 _block) onlyOwner public {
        require(_block > 0);
        uintStorage[keccak256("GENESIS_BLOCK")] = _block;
    }

    function CURRENT_ROUND() public view returns (uint256)  {
        uint256 _BLOCKS_PER_PERIOD = BLOCKS_PER_PERIOD();
        uint256 _GENESIS_BLOCK = GENESIS_BLOCK();
        uint256 _timeBlocks = block.number.sub( _GENESIS_BLOCK);
        uint256 _round = _timeBlocks.ceilDiv(_BLOCKS_PER_PERIOD);
        return _round;
    }
}
