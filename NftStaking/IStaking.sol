pragma solidity ^0.8.0;

interface IStaking {
    function deposit(
        uint256 _currPoolId,
        uint256 _globalId,
        uint256 _amount
    ) external;

    function claim(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId
    ) external returns (uint256 _reward);

    function withdraw(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId,
        uint256 _amount
    ) external returns (uint256 _reward);

    function getInfo(
        uint256 _globalId,
        uint256 _currPoolId,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 _reward,
            uint256 _boosterReward,
            uint256 _apr,
            uint256 _timeToClaimFreeze
        );

    function addCurrency(
        uint256 _currPoolId,
        string memory _name,
        uint256 _allocPoint
    ) external;

    function getPoolInfo(uint256 _currPoolId)
        external
        view
        returns (
            string memory name,
            uint256 allocPoint,
            uint256 commonAllocWeight
        );

    function getCurrPoolStats(uint256 _currPoolId)
        external
        view
        returns (uint256 count, uint256 amount);

    function activateBooster(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId
    ) external;

    function setBoostersActiveInterval(uint256 _intervalInSeconds) external;

    function getBoostersActiveInterval()
        external
        view
        returns (uint256 interval);

    function changeAllocPoint(uint256 _poolId, uint256 _newAllocPoint) external;

    function weightCorrector(uint256 _globalId) external;

    function boosterInfo(uint256 _assetId)
        external
        view
        returns (bool isActive, uint256 activeMult, uint256 boostersTimer);

    function emergencyBoosterClearer(uint256 _globalId) external;

    function getYieldInterval () external view returns (uint256 yieldInterval);

    function setYieldInterval (uint256 newYieldInterval) external;
}
