pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IOracle.sol";

contract Oracle is IOracle, Ownable {
    constructor() {
        Managers[msg.sender] = true;
    }

    //***Variables***//

    //***Mappings***//
    mapping(address => bool) internal Managers;
    mapping(address => bool) internal AllowedContracts;
    mapping(uint256 => uint256) internal Prices;

    //***Structs***//
    struct UpdatePriceStruct {
        uint256 currPoolId;
        uint256 value;
    }

    //***Modificators***//
    modifier onlyManager() {
        require(
            Managers[msg.sender],
            "Only managers allow to execute this operation"
        );
        _;
    }

    modifier onlyAllowedContract() {
        require(AllowedContracts[msg.sender], "Only allowedContracts allow to execute this operation");
        _;
    }

    //***Events***//

    //***Functions***//
    function getPrice(uint256 _currPoolId) external view override onlyAllowedContract returns (uint256 price) {
        if (Prices[_currPoolId] == 0) {
            revert();
        }
        return Prices[_currPoolId];
    }

    function setPrice(uint256 _currPoolId, uint256 _newPrice)
        public
        onlyManager
    {
        Prices[_currPoolId] = _newPrice;
    }

    function bulkSetPrice (bytes calldata data) external onlyManager {
        UpdatePriceStruct[] memory priceArr = abi.decode(
            data,
            (UpdatePriceStruct[])
        );
        uint256 arrLength = priceArr.length;
        require(arrLength > 0, "Empty array");
        for (uint256 i = 0; i < arrLength; i++) {
            setPrice(priceArr[i].currPoolId, priceArr[i].value);
        }
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

    function addAllowedAddr(address _addr) external onlyOwner {
        AllowedContracts[_addr] = true;
    }

    function removeAllowedAddr(address _addr) external onlyOwner {
        AllowedContracts[_addr] = false;
    }

    function isAllowed(address _addr)
        external
        view
        onlyOwner
        returns (bool _isManager)
    {
        return (AllowedContracts[_addr]);
    }


}
