pragma solidity ^0.8.0;

interface IController {
    function getAssetData(uint256 _globalId)
        external
        view
        returns (
            uint256 nftPoolId,
            uint256 currPoolId,
            uint256 amount,
            uint256 level,
            uint256 rarity,
            uint256 boostersMults
        );

    function transferBeacon(
        uint256 _poolId,
        address _poolAddr,
        address _from,
        address _to,
        uint256 _globalId
    ) external;

    function getBaseURL () external view returns (string memory _baseURL);

    function getBaseImgURL () external view returns (string memory _baseImgURL);
}
