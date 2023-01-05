pragma solidity ^0.4.25;
import "./Ownable.sol";

contract Permission is Ownable {
    modifier hasAdminRole() {
        require(isAdmin(msg.sender) || msg.sender == owner());
        _;
    }
    function isAdmin(address _address) public view returns (bool) {
        return boolStorage[keccak256(abi.encodePacked("admin", _address))];
    }
    
    function removeAdmin(address _address) onlyOwner public{
        boolStorage[keccak256(abi.encodePacked("admin", _address))] = false;
    }
    
    function addAdmin(address _address) onlyOwner public {
        require(_address != address(0));
        boolStorage[keccak256(abi.encodePacked("admin", _address))] = true;
    }
}