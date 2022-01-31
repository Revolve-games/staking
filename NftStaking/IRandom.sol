pragma solidity >=0.6.6;

interface IRandom {
  event Request(bytes32 requestId, address user, uint256 poolId, uint256 globalAssetId);
  event Response(bytes32 requestId);
  function getRandomNumber(address user, uint256 poolId, uint256 globalAssetId) external returns (bytes32 requestId);
  function addAllowedAddr(address _contract) external returns (bool);
  function removeAllowedAddr(address _contract) external returns (bool);
  function expandByRequest(bytes32 requestId, uint8 randomAmount) external view returns(uint256[] memory);
}