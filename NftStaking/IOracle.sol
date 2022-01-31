pragma solidity ^0.8.0;

interface IOracle {
  function getPrice(uint256 _currPoolId) external view returns (uint256 price);
}