// SPDX-License-Identifier: None
pragma solidity ^0.8.25;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    constructor() ERC721("ERC721Mock", "TT-721") { }

    function mint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
    }
}
