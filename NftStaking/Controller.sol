pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./INFT.sol";
import "./IOracle.sol";
import "./IRandom.sol";
import "./IStaking.sol";
import "./IController.sol";

contract Controller is IController, Ownable, ReentrancyGuard {
    constructor() {
        availableToReroll = 604800;
        Managers[msg.sender] = true;
        generationFee = 150000 * 10**9;
        boostersFee = 150000 * 10**9;
        levelsFee = 150000 * 10**9;
    }

    //***Variables***//
    uint256 public NFTPoolCounter;
    uint256 public assetCounter;
    uint256 public currencyPoolCounter;

    uint256 public availableToReroll;
    uint256 public generationFee;
    uint256 public boostersFee;
    uint256 public levelsFee;
    address public feeReceiver;
    address public rerollFeeReceiver;
    string public baseURL;
    string public baseImgURL;

    address public generator;
    IRandom internal Random;
    address public staking;
    IStaking internal Staking;
    address public oracle;
    IOracle internal Oracle;

    //***Mappings***//
    mapping(uint256 => INFT) NFTPoolsToIds;
    mapping(uint256 => Asset) public AssetsToIds;
    mapping(address => bool) internal Managers;
    mapping(uint256 => Currency) public CurrencyPools;

    //***Structs***//
    struct Asset {
        uint256 nftPoolId;
        uint256 currPoolId;
        uint256 amount;
        uint256 level;
        uint256 rarity;
        uint256 createdAt;
        uint256 boostersMults;
        uint256 unsyncLevel;
        uint256 unsyncBoostersMults;
        uint256 boostersUpdateAmount;
        uint256 levelsUpdateAmount;
        bool isStaked;
        bool isExist;
    }

    struct UpdateAssetStruct {
        uint256 globalId;
        uint256 value;
    }

    struct UpdateAssetBoosters {
        uint256 globalId;
        uint256 boostersMults;
    }

    struct Currency {
        IERC20 token;
        uint256 minimalAmount;
        uint256 maximalAmount;
        uint256 rerollPercent;
    }

    //***Modificators***//
    modifier onlyManager() {
        require(
            Managers[msg.sender],
            "Only managers allow to execute this operation"
        );
        _;
    }

    modifier onlyAssetOwner(uint256 _globalId) {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist??");
        uint256 poolId = AssetsToIds[_globalId].nftPoolId;
        INFT currPool = NFTPoolsToIds[poolId];
        // Maybe add to require "|| Managers[msg.sender]" ???
        require(
            currPool.getOwner(_globalId) == msg.sender,
            "Available for asset owner only"
        );
        _;
    }

    //***Events***//
    event AssetGenerated(
        address ownerAddres,
        bytes32 randomRequestId,
        uint256 assetPoolId,
        uint256 currencyPoolId,
        uint256 assetGlobalId,
        uint256 assetsCountInCurrencyPool,
        uint256 currencyPoolSummaryStakeAmount,
        uint256 assetStakedAmount,
        string data
    );
    event AssetReroll(
        address ownerAddress,
        bytes32 randomRequestId,
        uint256 assetGlobalId,
        uint256 assetsCountInCurrencyPool,
        uint256 currencyPoolSummaryStakeAmount
    );
    event AssetTransfer(
        uint256 assetPoolId,
        address assetPoolAddress,
        address addressFrom,
        address addressTo,
        uint256 assetGlobalId
    );
    event AssetUnstake(uint256 assetGlobalId, uint256 rewardAmount);
    event AssetUpdateLevel(uint256 assetGlobalId, uint256 level);
    event AssetUpdateBoosters(
        uint256 assetGlobalId,
        uint256 boostersSummaryMultiplier
    );
    event BoostersActivated(
        uint256 assetGlobalId,
        uint256 boostersSummaryMultiplier,
        uint256 startTimestamp,
        uint256 intervalInSeconds
    );
    event Claim(uint256 assetGlobalId, uint256 rewardAmount);
    event AddAssetPool(uint256 assetPoolId, address assetPoolContractAddress);
    event AddCurrencyPool(
        uint256 currencyPoolId,
        string currenctName,
        address currencyPoolTokenAddress,
        uint256 currencyPoolAllocPoint,
        uint256 minimalStakeAmount,
        uint256 rerollFeePercent
    );
    event UpdateCurrencyPoolBaseAPY(uint256 currencyPoolId, uint256 newAPY);
    event UpdateCurrencyPoolMultipliers(
        uint256 currencyPoolId,
        uint256 levelMultiplier,
        uint256 rarityMultiplier
    );

    //***NFT Pool Functions***//
    function addNFTPool(address _pool) external onlyManager {
        NFTPoolCounter += 1;
        INFT currPool = INFT(_pool);
        NFTPoolsToIds[NFTPoolCounter] = currPool;
        emit AddAssetPool(NFTPoolCounter, _pool);
    }

    function getNFTPool(uint256 _poolId)
        external
        view
        returns (
            address poolAddress,
            string memory name,
            string memory symbol
        )
    {
        INFT currPool = NFTPoolsToIds[_poolId];
        (string memory _name, string memory _symbol) = currPool.getPoolInfo();
        return (address(currPool), _name, _symbol);
    }

    function getNFTPoolsAmount() external view returns (uint256) {
        return (NFTPoolCounter);
    }

    //***Asset Functions***//
    function generateAsset(
        uint256 _poolId,
        uint256 _currPoolId,
        uint256 _amount,
        string calldata data
    ) external payable {
        require(
            _amount >= CurrencyPools[_currPoolId].minimalAmount,
            "Too low amount for generation"
        );
        require(
            _amount <= CurrencyPools[_currPoolId].maximalAmount,
            "Too big amount for generation"
        );
        require(msg.value >= generationFee, "Insufficient commission");
        payable(feeReceiver).transfer(generationFee);
        require(CurrencyPools[_currPoolId].token.transferFrom(
            msg.sender,
            address(this),
            _amount
        ), "Transfer error");
        assetCounter += 1;

        INFT currPool = NFTPoolsToIds[_poolId];
        currPool.mint(msg.sender, assetCounter);
        AssetsToIds[assetCounter].nftPoolId = _poolId;
        AssetsToIds[assetCounter].level = 1;
        AssetsToIds[assetCounter].amount = _amount;
        AssetsToIds[assetCounter].currPoolId = _currPoolId;
        AssetsToIds[assetCounter].createdAt = block.timestamp;
        AssetsToIds[assetCounter].isExist = true;

        (uint256 count, uint256 amount) = Staking.getCurrPoolStats(_currPoolId);

         bytes32 requestId = Random.getRandomNumber(msg.sender, _poolId, assetCounter);
         emit AssetGenerated (msg.sender, requestId, _poolId, _currPoolId, assetCounter, count, amount, _amount, data);
    }

    function rerollAsset(uint256 _globalId)
        external
        payable
        onlyAssetOwner(_globalId)
    {
        (bool _isAvailableToReroll, uint256 rerollAmount) = rerollHelper(
            _globalId
        );
        require(_isAvailableToReroll, "Time to reroll is over");
        require(msg.value >= rerollAmount, "Insufficient commission");
        payable(feeReceiver).transfer(generationFee);
        payable(rerollFeeReceiver).transfer(rerollAmount - generationFee);

        (uint256 count, uint256 amount) = Staking.getCurrPoolStats(
            AssetsToIds[_globalId].currPoolId
        );
         bytes32 requestId = Random.getRandomNumber(
             msg.sender,
             AssetsToIds[_globalId].currPoolId,
             _globalId
         );
         emit AssetReroll(msg.sender, requestId, _globalId, count, amount);
    }

    function rerollHelper(uint256 _globalId)
        public
        view
        returns (bool _isAvailableToReroll, uint256 rerollFee)
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        rerollFee =
            (AssetsToIds[_globalId].amount *
                CurrencyPools[AssetsToIds[_globalId].currPoolId]
                    .rerollPercent) /
            10000;
        uint256 rerollAmount = (rerollFee *
            Oracle.getPrice(AssetsToIds[_globalId].currPoolId)) /
            Oracle.getPrice(0);
        bool isAvailToReroll = AssetsToIds[_globalId].createdAt +
            availableToReroll >
            block.timestamp;
        if (isAvailToReroll) {
            rerollFee = generationFee + rerollAmount;
        }
        return (isAvailToReroll, rerollFee);
    }

    function fulfillAsset(uint256 _globalId, uint256 _rarity)
        external
        onlyManager
        nonReentrant
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        AssetsToIds[_globalId].rarity = _rarity;
        uint256 _currPoolId = AssetsToIds[_globalId].currPoolId;
        uint256 _amount = AssetsToIds[_globalId].amount;
        if (!AssetsToIds[_globalId].isStaked) {
            Staking.deposit(_currPoolId, _globalId, _amount);
            AssetsToIds[_globalId].isStaked = true;
        } else {
            Staking.weightCorrector(_globalId);
        }
    }

    function getAssetData(uint256 _globalId)
        public
        view
        override
        returns (
            uint256 nftPoolId,
            uint256 currPoolId,
            uint256 amount,
            uint256 level,
            uint256 rarity,
            uint256 boostersMults
        )
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        return (
            AssetsToIds[_globalId].nftPoolId,
            AssetsToIds[_globalId].currPoolId,
            AssetsToIds[_globalId].amount,
            AssetsToIds[_globalId].level,
            AssetsToIds[_globalId].rarity,
            AssetsToIds[_globalId].boostersMults
        );
    }

    function getAssetUrl(uint256 _globalId)
        external
        view
        returns (string memory tokenURL)
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        return (
            NFTPoolsToIds[AssetsToIds[_globalId].nftPoolId].tokenURL(_globalId)
        );
    }

    function syncAsset(uint256 _globalId)
        external
        payable
        onlyAssetOwner(_globalId)
        nonReentrant
    {
        require(
            AssetsToIds[_globalId].boostersUpdateAmount > 0 ||
                AssetsToIds[_globalId].levelsUpdateAmount > 0,
            "Asset is already synchronized"
        );
        uint256 fee = AssetsToIds[_globalId].boostersUpdateAmount *
            boostersFee +
            AssetsToIds[_globalId].levelsUpdateAmount *
            levelsFee;
        require(msg.value >= fee, "Insufficient commission");
        payable(feeReceiver).transfer(fee);
        AssetsToIds[_globalId].level = AssetsToIds[_globalId].unsyncLevel;
        AssetsToIds[_globalId].boostersMults = AssetsToIds[_globalId]
            .unsyncBoostersMults;
        AssetsToIds[_globalId].boostersUpdateAmount = 0;
        AssetsToIds[_globalId].levelsUpdateAmount = 0;
        if (AssetsToIds[_globalId].isStaked) {
            Staking.weightCorrector(_globalId);
        }
    }

    function syncHelper(uint256 _globalId)
        external
        view
        returns (
            uint256 levelUpdateFee,
            uint256 levelUpdateAmount,
            uint256 boosterUpdateFee,
            uint256 boosterUpdateAmount,
            uint256 summaryFee
        )
    {
        uint256 fee = AssetsToIds[_globalId].boostersUpdateAmount *
            boostersFee +
            AssetsToIds[_globalId].levelsUpdateAmount *
            levelsFee;
        return (
            levelsFee,
            AssetsToIds[_globalId].levelsUpdateAmount,
            boostersFee,
            AssetsToIds[_globalId].boostersUpdateAmount,
            fee
        );
    }

    function updateAssetLevel(uint256 _globalId, uint256 _level)
        public
        onlyManager
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        AssetsToIds[_globalId].levelsUpdateAmount += 1;
        AssetsToIds[_globalId].unsyncLevel = _level;
        emit AssetUpdateLevel(_globalId, _level);
    }

    function bulkUpdateAssetLevel(bytes calldata data) external onlyManager {
        UpdateAssetStruct[] memory assetsArr = abi.decode(
            data,
            (UpdateAssetStruct[])
        );
        uint256 arrLength = assetsArr.length;
        require(arrLength > 0, "Empty array");
        for (uint256 i = 0; i < arrLength; i++) {
            updateAssetLevel(assetsArr[i].globalId, assetsArr[i].value);
        }
    }

    function updateAssetBoosters(uint256 _globalId, uint256 _boostersMult)
        public
        onlyManager
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        AssetsToIds[_globalId].boostersUpdateAmount += 1;
        AssetsToIds[_globalId].unsyncBoostersMults += _boostersMult;
        emit AssetUpdateBoosters(_globalId, _boostersMult);
    }

    function bulkUpdateAssetBoosters(bytes calldata data) external onlyManager {
        UpdateAssetStruct[] memory assetsArr = abi.decode(
            data,
            (UpdateAssetStruct[])
        );
        uint256 arrLength = assetsArr.length;
        require(arrLength > 0, "Empty array");
        for (uint256 i = 0; i < arrLength; i++) {
            updateAssetBoosters(assetsArr[i].globalId, assetsArr[i].value);
        }
    }

    function unstakeAsset(uint256 _globalId) public onlyAssetOwner(_globalId) nonReentrant {
        require(
            AssetsToIds[_globalId].boostersUpdateAmount == 0 &&
                AssetsToIds[_globalId].levelsUpdateAmount == 0,
            "Synchronize asset first"
        );
        uint256 _currPoolId = AssetsToIds[_globalId].currPoolId;
        uint256 _amount = AssetsToIds[_globalId].amount;
        uint256 poolId = AssetsToIds[_globalId].nftPoolId;
        INFT currPool = NFTPoolsToIds[poolId];
        uint256 reward;
        if (AssetsToIds[_globalId].isStaked) {
            reward = Staking.withdraw(
                _globalId,
                currPool.getOwner(_globalId),
                _currPoolId,
                _amount
            );
        }
        currPool.burn(_globalId);
        require(CurrencyPools[AssetsToIds[_globalId].currPoolId].token.transfer(
            msg.sender,
            AssetsToIds[_globalId].amount
        ), "Transfer error");
        AssetsToIds[_globalId].amount = 0;
        AssetsToIds[_globalId].isExist = false;
        emit AssetUnstake(_globalId, reward);
    }

    function bulkUnstakeAsset(uint256[] calldata _idsArray) external {
        uint256 length = _idsArray.length;
        require(length > 0, "Empty array");

        for (uint256 i = 0; i < length; i++) {
            unstakeAsset(_idsArray[i]);
        }
    }

    function getUpdateAmount(uint256 _globalId)
        external
        view
        returns (uint256 levels, uint256 boosters)
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        return (
            AssetsToIds[_globalId].levelsUpdateAmount,
            AssetsToIds[_globalId].boostersUpdateAmount
        );
    }

    function activateBoosters(uint256 _globalId)
        external
        onlyAssetOwner(_globalId)
        nonReentrant
    {
        require(
            AssetsToIds[_globalId].boostersUpdateAmount == 0 &&
                AssetsToIds[_globalId].levelsUpdateAmount == 0,
            "Synchronize asset first"
        );
        require(
            AssetsToIds[_globalId].boostersMults > 0,
            "You don't have any boosters"
        );
        require(AssetsToIds[_globalId].isStaked, "Asset is not staked");

        uint256 mult = AssetsToIds[_globalId].boostersMults;
        uint256 poolId = AssetsToIds[_globalId].nftPoolId;
        INFT currPool = NFTPoolsToIds[poolId];
        uint256 _currPoolId = AssetsToIds[_globalId].currPoolId;
        Staking.activateBooster(
            _globalId,
            currPool.getOwner(_globalId),
            _currPoolId
        );
        AssetsToIds[_globalId].boostersMults = 0;
        uint256 interval = Staking.getBoostersActiveInterval();

        emit BoostersActivated(_globalId, mult, block.timestamp, interval);
    }

    function boosterInfo(uint256 _globalId)
        external
        view
        returns (bool _isBoosterActive, uint256 activeMult, uint256 boostersTimer, bool isBoostersAvail, uint256 availBoostersMult)
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        (_isBoosterActive, activeMult, boostersTimer) = Staking.boosterInfo(_globalId);
        if (!_isBoosterActive && AssetsToIds[_globalId].boostersMults > 0) {
            isBoostersAvail = true;
            availBoostersMult = AssetsToIds[_globalId].boostersMults;
        }
        return (_isBoosterActive, activeMult, boostersTimer, isBoostersAvail, availBoostersMult);
    }

    //***Staking Functions***//
    function addCurrencyPool(
        address _tokenAddress,
        string calldata _name,
        uint256 _allocPoint,
        uint256 _minimalAmount,
        uint256 _maximalAmount,
        uint256 _rerollPercent
    ) external onlyOwner {
        currencyPoolCounter += 1;
        Staking.addCurrency(currencyPoolCounter, _name, _allocPoint);
        CurrencyPools[currencyPoolCounter].token = IERC20(_tokenAddress);
        CurrencyPools[currencyPoolCounter].minimalAmount = _minimalAmount;
        CurrencyPools[currencyPoolCounter].maximalAmount = _maximalAmount;
        CurrencyPools[currencyPoolCounter].rerollPercent = _rerollPercent;
        emit AddCurrencyPool(
            currencyPoolCounter,
            _name,
            _tokenAddress,
            _allocPoint,
            _minimalAmount,
            _rerollPercent
        );
    }

    function changeCurrencyPoolAllocPoint(
        uint256 _currPoolId,
        uint256 _newAllocPoint
    ) external onlyOwner {
        Staking.changeAllocPoint(_currPoolId, _newAllocPoint);
    }

    function changeRerollPercent(uint256 _currPoolId, uint256 _newRerollPercent)
        external
        onlyOwner
    {
        CurrencyPools[_currPoolId].rerollPercent = _newRerollPercent;
    }

    function changeMinMaxAmount(
        uint256 _currPoolId,
        uint256 _newMinAmount,
        uint256 _newMaxAmount
    ) external onlyOwner {
        CurrencyPools[_currPoolId].minimalAmount = _newMinAmount;
        CurrencyPools[_currPoolId].maximalAmount = _newMaxAmount;
    }

    function getCurrencyPoolInfo(uint256 _currPoolId)
        external
        view
        returns (
            string memory name,
            address tokenAddress,
            uint256 allocPoint,
            uint256 commonAllocWeight,
            uint256 minAmount,
            uint256 maxAmount,
            uint256 rerollPercent
        )
    {
        (name, allocPoint, commonAllocWeight) = Staking.getPoolInfo(
            _currPoolId
        );
        tokenAddress = address(CurrencyPools[currencyPoolCounter].token);
        minAmount = CurrencyPools[currencyPoolCounter].minimalAmount;
        maxAmount = CurrencyPools[currencyPoolCounter].maximalAmount;
        rerollPercent = CurrencyPools[currencyPoolCounter].rerollPercent;

        return (
            name,
            tokenAddress,
            allocPoint,
            commonAllocWeight,
            minAmount,
            maxAmount,
            rerollPercent
        );
    }

    function getStakingInfo(uint256 _globalId)
        external
        view
        returns (
            uint256 reward,
            uint256 boosterReward,
            uint256 apr,
            uint256 amount,
            uint256 timeToClaimFreeze
        )
    {
        require(AssetsToIds[_globalId].isExist, "Asset is not exist");
        uint256 _currPoolId = AssetsToIds[_globalId].currPoolId;
        uint256 relativeAmount;
        if (_currPoolId == 1) {
            relativeAmount = AssetsToIds[_globalId].amount;
        } else {
            relativeAmount =
                (AssetsToIds[_globalId].amount * Oracle.getPrice(_currPoolId)) /
                Oracle.getPrice(1);
        }
        if (AssetsToIds[_globalId].isStaked) {
            (reward, boosterReward, apr, timeToClaimFreeze) = Staking.getInfo(
                _globalId,
                _currPoolId,
                relativeAmount
            );
        }
        return (reward, boosterReward, apr, AssetsToIds[_globalId].amount, timeToClaimFreeze);
    }

    function claim(uint256 _globalId) public onlyAssetOwner(_globalId) {
        require(
            AssetsToIds[_globalId].boostersUpdateAmount == 0 &&
                AssetsToIds[_globalId].levelsUpdateAmount == 0,
            "Synchronize asset first"
        );
        uint256 _currPoolId = AssetsToIds[_globalId].currPoolId;
        uint256 poolId = AssetsToIds[_globalId].nftPoolId;
        uint256 reward;
        INFT currPool = NFTPoolsToIds[poolId];
        if (AssetsToIds[_globalId].isStaked) {
            reward = Staking.claim(
                _globalId,
                currPool.getOwner(_globalId),
                _currPoolId
            );
        }
        emit Claim(_globalId, reward);
    }

    function bulkClaim(uint256[] calldata _idsArray) external {
        uint256 length = _idsArray.length;
        require(length > 0, "Empty array");
        for (uint256 i = 0; i < length; i++) {
            claim(_idsArray[i]);
        }
    }

    //***Setting Functions***//
    function changeGenerator(address _addr) external onlyOwner {
        require(_addr != address(0), "Zero address");
        generator = _addr;
        Random = IRandom(_addr);
    }

    function changeOracle(address _addr) external onlyOwner {
        require(_addr != address(0), "Zero address");
        oracle = _addr;
        Oracle = IOracle(_addr);
    }

    function changeStaking(address _addr) external onlyOwner {
        require(_addr != address(0), "Zero address");
        staking = _addr;
        Staking = IStaking(_addr);
    }

    function setAvailableToReroll(uint256 _intervalInSeconds)
        external
        onlyOwner
    {
        availableToReroll = _intervalInSeconds;
    }

    function setBoostersActiveInterval(uint256 _intervalInSeconds)
        external
        onlyOwner
    {
        Staking.setBoostersActiveInterval(_intervalInSeconds);
    }

    function setYieldInterval (uint256 newYieldInterval) external onlyOwner {
        Staking.setYieldInterval(newYieldInterval);
    }

    function getYieldInterval () external view returns (uint256) {
       return (Staking.getYieldInterval());
    }

    function addManager(address _addr) external onlyOwner {
        Managers[_addr] = true;
    }

    function removeManager(address _addr) external onlyOwner {
        Managers[_addr] = false;
    }

    function isManager(address _addr)
        external
        view
        onlyOwner
        returns (bool _isManager)
    {
        return (Managers[_addr]);
    }

    function transferBeacon(
        uint256 _poolId,
        address _poolAddr,
        address _from,
        address _to,
        uint256 _globalId
    ) public override {
        require(
            address(NFTPoolsToIds[_poolId]) == _poolAddr,
            "Sender is not a NFT contract"
        );
        emit AssetTransfer(_poolId, _poolAddr, _from, _to, _globalId);
    }

    function changeTrxFee(
        uint256 _generationFeeInWei,
        uint256 _updateLevelsFeeInWei,
        uint256 _updateBoostersFeeOnWei
    ) external onlyOwner {
        generationFee = _generationFeeInWei;
        levelsFee = _updateLevelsFeeInWei;
        boostersFee = _updateBoostersFeeOnWei;
    }

    function changeFeeReciever(address _addr) external onlyOwner {
        require(_addr != address(0), "Zero address");
        feeReceiver = _addr;
    }

    function changeRerollFeeReceiver(address _addr) external onlyOwner {
        require(_addr != address(0), "Zero address");
        rerollFeeReceiver = _addr;
    }

    function getBaseURL()
        external
        view
        override
        returns (string memory _baseURL)
    {
        return baseURL;
    }

    function changeBaseURL(string memory _newBaseURL) external onlyOwner {
        baseURL = _newBaseURL;
    }

    function getBaseImgURL()
        external
        view
        override
        returns (string memory _baseImgURL)
    {
        return baseImgURL;
    }

    function changeBaseImgURL(string memory _newBaseImgURL) external onlyOwner {
        baseImgURL = _newBaseImgURL;
    }

    function tokensWithdraw(
        address _token,
        address _reciever,
        uint256 _amount
    ) external onlyOwner {
        IERC20 token = IERC20(_token);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Insufficient balance for transaction"
        );
        require(token.transfer(_reciever, _amount), "Transfer error");
    }

    function emergencyWithdraw(uint256 _globalId)
        external
        onlyAssetOwner(_globalId)
        nonReentrant
    {
        require(
            AssetsToIds[_globalId].boostersUpdateAmount == 0 &&
                AssetsToIds[_globalId].levelsUpdateAmount == 0,
            "Synchronize asset first"
        );
        uint256 poolId = AssetsToIds[_globalId].nftPoolId;
        INFT currPool = NFTPoolsToIds[poolId];
        currPool.burn(_globalId);
        require(CurrencyPools[AssetsToIds[_globalId].currPoolId].token.transfer(
            msg.sender,
            AssetsToIds[_globalId].amount
        ), "Transfer error");
        AssetsToIds[_globalId].amount = 0;
        if (AssetsToIds[_globalId].isStaked) {
            Staking.weightCorrector(_globalId);
            Staking.emergencyBoosterClearer(_globalId);
        }
        AssetsToIds[_globalId].isExist = false;
        emit AssetUnstake(_globalId, 0);
    }
}
