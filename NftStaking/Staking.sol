pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IStaking.sol";
import "./IController.sol";
import "./IOracle.sol";

contract StakingNFT is IStaking, Ownable, ReentrancyGuard {
    constructor(address _ctrl, address _rpg) {
        controller = _ctrl;
        Controller = IController(_ctrl);
        rpgToken = _rpg;
        yieldInterval = 2629743;
        boostersActiveInterval = 259200;
    }

    //***Variables***//
    address public controller;
    IController internal Controller;
    address public rpgToken;
    uint256 public boostersDebt;
    uint256 public boostersActiveInterval;
    uint256 public yieldInterval;
    uint256 public poolCommonWeight;

    //***Mappings***//
    mapping(uint256 => asset) private assetsToId;
    mapping(uint256 => assetBooster) private assetBoostersToAssetsId;
    mapping(uint256 => currencyPool) public currencyPoolsToId;

    //***Structs***//
    struct asset {
        uint256 timestamp;
        uint256 weight;
    }

    struct currencyPool {
        string name;
        uint256 count;
        uint256 allocPoint;
        uint256 sum;
        uint256 commonWeight;
        bool isExist;
    }

    struct assetBooster {
        uint256 multiplier;
        uint256 startTime;
        uint256 endTime;
        uint256 debt;
    }

    //***Modificators***//
    modifier onlyController() {
        require(msg.sender == controller, "Only controller allow func calls");
        _;
    }

    //***Events***//
    event Claim(uint256 reward);
    event TestStatsUpdate(uint256, uint256, uint256, uint256);

    //***Functions***//
    function addCurrency(
        uint256 _currPoolId,
        string memory _name,
        uint256 _allocPoint
    ) external override onlyController {
        require(
            !currencyPoolsToId[_currPoolId].isExist,
            "Pool with current id has been already existed"
        );
        currencyPoolsToId[_currPoolId].name = _name;
        currencyPoolsToId[_currPoolId].allocPoint = _allocPoint;
        poolCommonWeight += _allocPoint;
        currencyPoolsToId[_currPoolId].isExist = true;
    }

    function getPoolInfo(uint256 _currPoolId)
        external
        view
        override
        returns (
            string memory name,
            uint256 allocPoint,
            uint256 commonAllocWeight
        )
    {
        require(
            currencyPoolsToId[_currPoolId].isExist,
            "Currency pool is not exist"
        );
        return (
            currencyPoolsToId[_currPoolId].name,
            currencyPoolsToId[_currPoolId].allocPoint,
            poolCommonWeight
        );
    }

    function changeController(address _ctrl) external onlyOwner {
        controller = _ctrl;
        Controller = IController(_ctrl);
    }

    function deposit(
        uint256 _currPoolId,
        uint256 _globalId,
        uint256 _amount
    ) external override onlyController {
        require(currencyPoolsToId[_currPoolId].isExist, "Pool is not exist");
        weightCorrector(_globalId);
        currencyPoolsToId[_currPoolId].sum += _amount;
        currencyPoolsToId[_currPoolId].count += 1;
        assetsToId[_globalId].timestamp = block.timestamp;
    }

    function activateBooster(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId
    ) public override onlyController nonReentrant {
        require(
            assetBoostersToAssetsId[_globalId].endTime < block.timestamp,
            "Booster is active now"
        );

        claim(_globalId, _owner, _currPoolId);

        IERC20 rpg = IERC20(rpgToken);
        uint256 balance = rpg.balanceOf(address(this));
        uint256 yieldPerSecond = (balance - boostersDebt) / yieldInterval;

        (
            uint256 commonWeight,
            uint256 assetWeight
        ) = _weightCorrectorForBoosters(_globalId);

        uint256 timeDifference = boostersActiveInterval;
        uint256 poolPercent = (currencyPoolsToId[_currPoolId].allocPoint *
            1e18) / poolCommonWeight;
        uint256 assetPercent = (assetWeight * 1e18) / commonWeight;
        uint256 reward = (yieldPerSecond *
            timeDifference *
            poolPercent *
            assetPercent) / 1e36;
        assetBoostersToAssetsId[_globalId].debt = reward;
        boostersDebt += reward;
    }

    function boosterInfo(uint256 _assetId)
        external
        view
        override
        onlyController
        returns (bool isActive, uint256 activeMult, uint256 boostersTimer)
    {
        isActive = assetBoostersToAssetsId[_assetId].endTime > block.timestamp;
        if (isActive) {
            activeMult = assetBoostersToAssetsId[_assetId].multiplier;
            boostersTimer = assetBoostersToAssetsId[_assetId].endTime - block.timestamp;
        }
        return (isActive, activeMult, boostersTimer);
    }

    function _calc(uint256 _globalId, uint256 _currPoolId)
        internal
        view
        returns (uint256 reward, uint256 boosterReward)
    {
        IERC20 rpg = IERC20(rpgToken);
        uint256 balance = rpg.balanceOf(address(this));
        uint256 yieldPerSecond = (balance - boostersDebt) / yieldInterval;

        uint256 timeDifference = block.timestamp -
            assetsToId[_globalId].timestamp;
        if (timeDifference > yieldInterval) {
            timeDifference = yieldInterval;
        }
        if (
            assetBoostersToAssetsId[_globalId].endTime < block.timestamp &&
            assetBoostersToAssetsId[_globalId].endTime >
            assetBoostersToAssetsId[_globalId].startTime
        ) {
            uint256 boosterInterval = assetBoostersToAssetsId[_globalId]
                .endTime - assetBoostersToAssetsId[_globalId].startTime;
            timeDifference -= boosterInterval;
            boosterReward = assetBoostersToAssetsId[_globalId].debt;
        } else if (
            assetBoostersToAssetsId[_globalId].endTime >
            assetBoostersToAssetsId[_globalId].startTime
        ) {
            uint256 boosterInterval = assetBoostersToAssetsId[_globalId]
                .endTime - assetBoostersToAssetsId[_globalId].startTime;
            uint256 currentBoosterInterval = block.timestamp -
                assetBoostersToAssetsId[_globalId].startTime;
            boosterReward =
                (assetBoostersToAssetsId[_globalId].debt *
                    currentBoosterInterval) /
                boosterInterval;
        }
        uint256 poolPercent = (currencyPoolsToId[_currPoolId].allocPoint *
            1e18) / poolCommonWeight;
        uint256 assetPercent = (assetsToId[_globalId].weight * 1e18) /
            currencyPoolsToId[_currPoolId].commonWeight;
        reward =
            (yieldPerSecond * timeDifference * poolPercent * assetPercent) /
            1e36;
    }

    function claim(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId
    ) public override onlyController returns (uint256) {
        (uint256 reward, uint256 boosterReward) = _calc(_globalId, _currPoolId);
        if (boosterReward > 0) {
            boostersDebt -= boosterReward;
            assetBoostersToAssetsId[_globalId].debt -= boosterReward;
            assetBoostersToAssetsId[_globalId].startTime = block.timestamp;
        }
        assetsToId[_globalId].timestamp = block.timestamp;
        IERC20 rpg = IERC20(rpgToken);
        rpg.transfer(_owner, (reward + boosterReward));
        emit Claim(reward);
        return (reward + boosterReward);
    }

    function withdraw(
        uint256 _globalId,
        address _owner,
        uint256 _currPoolId,
        uint256 _amount
    ) public override onlyController returns (uint256) {
        uint256 reward = claim(_globalId, _owner, _currPoolId);

        currencyPoolsToId[_currPoolId].commonWeight -= assetsToId[_globalId]
            .weight;
        currencyPoolsToId[_currPoolId].sum -= _amount;
        currencyPoolsToId[_currPoolId].count -= 1;
        return reward;
    }

    function getInfo(
        uint256 _globalId,
        uint256 _currPoolId,
        uint256 _amount
    )
        external
        view
        override
        onlyController
        returns (uint256 reward, uint256 boosterReward, uint256 apr, uint256 timeToClaimFreeze)
    {
        (reward, boosterReward) = _calc(_globalId, _currPoolId);
        uint256 period = block.timestamp - assetsToId[_globalId].timestamp;
        if (period >= yieldInterval) {
            period = yieldInterval;
            timeToClaimFreeze = 0;
        } else {
           timeToClaimFreeze = yieldInterval - period;
        }
        if (period > 0) {
            apr = (((reward + boosterReward) / period) * 31556926 * 10000) /
            _amount;
        }
        return (reward, boosterReward, apr, timeToClaimFreeze);
    }

    function getBoostersActiveInterval()
        external
        view
        override
        returns (uint256 interval)
    {
        return (boostersActiveInterval);
    }

    function getYieldInterval () external override view returns (uint256) {
        return (yieldInterval);
    }

    function setYieldInterval (uint256 newYieldInterval) external override onlyController {
        yieldInterval = newYieldInterval;
    }

    function changeAllocPoint(uint256 _poolId, uint256 _newAllocPoint)
        external
        override
        onlyController
    {
        poolCommonWeight -= currencyPoolsToId[_poolId].allocPoint;
        currencyPoolsToId[_poolId].allocPoint = _newAllocPoint;
        poolCommonWeight += _newAllocPoint;
    }

    function getCurrPoolStats(uint256 _currPoolId)
        external
        view
        override
        returns (uint256 count, uint256 amount)
    {
        return (
            currencyPoolsToId[_currPoolId].count,
            currencyPoolsToId[_currPoolId].sum
        );
    }

    function setBoostersActiveInterval(uint256 _intervalInSeconds)
        external
        override
        onlyController
    {
        boostersActiveInterval = _intervalInSeconds;
    }

    function weightCorrector(uint256 _globalId) public override onlyController {
        (
            uint256 nftPoolId,
            uint256 currPoolId,
            uint256 amount,
            uint256 level,
            uint256 rarity,
            uint256 boostersMults
        ) = Controller.getAssetData(_globalId);

        uint256 one = assetsToId[_globalId].weight;
        uint256 three = currencyPoolsToId[currPoolId].commonWeight;

        currencyPoolsToId[currPoolId].commonWeight -= assetsToId[_globalId]
            .weight;
        assetsToId[_globalId].weight =
            (100 + level) *
            (100 + rarity * 10) *
            (amount * 100);
        currencyPoolsToId[currPoolId].commonWeight += assetsToId[_globalId]
            .weight;

        uint256 two = assetsToId[_globalId].weight;
        uint256 four = currencyPoolsToId[currPoolId].commonWeight;

        emit TestStatsUpdate(one, two, three, four);
    }

    function _weightCorrectorForBoosters(uint256 _globalId)
        internal
        returns (uint256 commonWeight, uint256 assetWeight)
    {
        (
            uint256 nftPoolId,
            uint256 currPoolId,
            uint256 amount,
            uint256 level,
            uint256 rarity,
            uint256 boostersMults
        ) = Controller.getAssetData(_globalId);
        assetBoostersToAssetsId[_globalId].startTime = block.timestamp;
        assetBoostersToAssetsId[_globalId].endTime =
            block.timestamp +
            boostersActiveInterval;
        assetBoostersToAssetsId[_globalId].multiplier = boostersMults;
        commonWeight =
            currencyPoolsToId[currPoolId].commonWeight -
            assetsToId[_globalId].weight;
        assetWeight =
            (100 + level) *
            (100 + rarity * 10) *
            (amount * 100) *
            boostersMults;
        commonWeight += assetWeight;
    }

    function tokensWithdraw(
        address _token,
        address _receiver,
        uint256 _amount
    ) external onlyOwner {
        IERC20 token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Insufficient balance for transaction"
        );
        token.transfer(_receiver, _amount);
    }

    function emergencyBoosterClearer(uint256 _globalId)
        external
        override
        onlyController
    {
        uint256 debt = assetBoostersToAssetsId[_globalId].debt;
        if (debt > 0) {
            boostersDebt -= debt;
        }
    }
}
