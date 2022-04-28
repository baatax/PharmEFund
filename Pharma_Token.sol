// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//Add override function to change increaseAllowance to use tx.origin instead of msg.sender

contract PharmaToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("PharmaToken", "PTK") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    function Exchange_Tokens(uint256 amt) public{
        _burn(msg.sender, amt);
        payable(msg.sender).transfer(amt);
    }
    function Buy_Tokens() public payable{
        _mint(msg.sender, msg.value);
    }
    function empty_funds(uint256 amount) public onlyOwner{
        payable(msg.sender).transfer(amount);
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        address owner = tx.origin;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }
    
}
