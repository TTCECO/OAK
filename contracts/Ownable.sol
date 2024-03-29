pragma solidity ^0.4.25;

import "./EternalStorage.sol";

contract Ownable is EternalStorage {
    modifier onlyOwner() {
        require(msg.sender == owner());
        _;
    }

    function owner() public view returns (address) {
        return addressStorage[keccak256("owner")];
    }

    function transferOwnership(address newOwner) public onlyOwner {
        setOwner(newOwner);
    }
    
    function setOwner(address newOwner) internal {
        require(newOwner != address(0));
        addressStorage[keccak256("owner")] = newOwner;
    }
}