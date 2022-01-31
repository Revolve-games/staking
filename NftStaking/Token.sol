pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
  constructor (string memory _name, string memory _symbol) ERC20(_name, _symbol){}



  function mint (address _addr, uint256 _amount) public {
    _mint(_addr, _amount);
  }
}