// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VALORO is ERC20, Ownable {

    constructor() ERC20("VALORO", "VAL") {}

    function mint(address to, uint256 amount) public onlyOwner{
        _mint(to, amount * 10 ** 18);
    }

    function increaseAllowance(address adressOwner, address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = adressOwner;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

}