// SPDX-License-Identifier: None
pragma solidity ^0.8.25;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor() ERC20("ERC20Mock", "TT-20") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
