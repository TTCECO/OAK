pragma solidity ^0.4.25;

contract EternalStorage{
    mapping(bytes32 => uint256) internal uintStorage;
    mapping(bytes32 => string) internal stringStorage;
    mapping(bytes32 => address) internal addressStorage;
    mapping(bytes32 => bytes) internal bytesStorage;
    mapping(bytes32 => bool) internal boolStorage;
    mapping(bytes32 => int256) internal intStorage;
    mapping(bytes32 => mapping (bytes32 => bool)) internal mapStorage;
    mapping(bytes32 => uint256[]) internal uintArrayStorage;
    mapping(bytes32 => address[]) internal addressArrayStorage;
}