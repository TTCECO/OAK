pragma solidity ^0.4.25;
interface RoundCalendar{
    function GENESIS_BLOCK() external view returns (uint256);
    function BLOCKS_PER_PERIOD() external view returns (uint256);
    function CURRENT_ROUND() external view returns (uint256);
}
