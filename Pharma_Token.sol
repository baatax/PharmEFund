// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PharmaToken is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("PharmaToken", "PTK") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function Buy_Tokens() public payable{
        _mint(msg.sender, msg.value);
    }
    function empty_funds() public onlyOwner{
        payable(msg.sender).transfer(address(this).balance);
    }
}
