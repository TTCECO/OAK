pragma solidity ^0.4.25;

interface IERC20 {
    function transfer(address to, uint256 value) external;
    function transferFrom(address from, address to, uint256 value) external;
    function balanceOf(address tokenOwner)  external returns (uint balance);
    function mintTo(address to, uint256 value) external returns (bool);
}