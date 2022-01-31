// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./INFT.sol";
import "./IController.sol";

contract NFT is INFT, ERC721, Ownable {
    using Strings for uint256;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _chainId,
        uint256 _poolId,
        address _ctrl
    ) ERC721(_name, _symbol) {
        controller = _ctrl;
        Controller = IController(_ctrl);
        poolId = _poolId;
        chainId = _chainId;
    }

    //***Variables***//
    address public controller;
    IController internal Controller;
    uint256 internal poolId;
    uint256 internal chainId;
    string internal baseURI;

    //***Mappings***//
    mapping(uint256 => string) internal tokensURIs;

    //***Structs***//
    struct mintStruct {
        address to;
        uint256 globalId;
    }

    //***Modificators***//
    modifier onlyController() {
        require(
            msg.sender == controller,
            "Only controller allow to execute this operation"
        );
        _;
    }

    //***Events***//

    //***Functions***//
    function getPoolInfo () external view override returns (string memory, string memory) {
        return (name(), symbol());
    }

    function getOwner (uint256 _globalId) view public override returns (address) {
        return ownerOf(_globalId);
    }

    function isExist (uint256 _globalId) view external override returns (bool) {
       return _exists(_globalId);
    }

    function mint(address _to, uint256 _globalId) public override onlyController {
        _safeMint(_to, _globalId);
    }

    function burn(uint256 _globalId) public onlyController override {
        require(_exists(_globalId), "Token doesn't exist");
        address from = getOwner(_globalId);
        _burn(_globalId);
        transferBeacon(from, address(0), _globalId);
    }

    function tokenURI(uint256 _globalId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_globalId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return
            bytes(Controller.getBaseImgURL()).length > 0
                ? string(
                    abi.encodePacked(
                        Controller.getBaseImgURL(),
                        chainId.toString(),
                        "/",
                        poolId.toString(),
                        "/",
                        _globalId.toString(),
                        ".png"
                    )
                )
                : "";
    }

       function tokenURL(uint256 _globalId)
        external
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_globalId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return
            bytes(Controller.getBaseImgURL()).length > 0
                ? string(
                    abi.encodePacked(
                        Controller.getBaseURL(),
                        chainId.toString(),
                        "/",
                        poolId.toString(),
                        "/",
                        _globalId.toString()
                    )
                )
                : "";
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
        transferBeacon(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
        transferBeacon(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
        transferBeacon(from, to, tokenId);
    }

    function transferBeacon (address _from, address _to, uint256 _tokenId) internal {
        Controller.transferBeacon(poolId, address(this), _from, _to, _tokenId);
    }
}
