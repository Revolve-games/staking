pragma solidity ^0.8.0;
interface INFT {
  function mint(address _to, uint256 _globalId) external;
  function burn(uint256 _globalId) external;
  function getOwner (uint256 _globalId) view external returns (address);
  function isExist (uint256 _globalId) view external returns (bool);
  function getPoolInfo () external view returns (string memory name, string memory symbol);
  function tokenURL(uint256 _globalId) external view returns (string memory);
}