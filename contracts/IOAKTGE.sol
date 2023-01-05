pragma solidity ^0.4.25;
interface OAKTGE {
    function IS_ROUND_RESULTED(uint256 _roundId) external returns (bool) ;
    function ROUND_ACN_REWARD(uint256 _roundId) external returns(uint256);
    function CAL_ROUND_ACN_REWARD(uint256 _roundId) external returns(uint256);
}