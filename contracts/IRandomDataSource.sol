pragma solidity ^0.4.25;

interface RandomDataSource {
    function isRandomSelected(uint256 _roundId, uint256 _index)  external returns (bool);
    function randomIndexCount(uint256 _roundId)  external returns(uint256);
}