// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DCAOrderLib.sol";

contract DCAOrderToken is ERC721, Ownable {
    using DCAOrderLib for DCAOrderLib.DCAOrder;

    // Mapping from token ID to order data
    mapping(uint256 => DCAOrderLib.DCAOrder) public orders;

    constructor() ERC721("DCA Order Token", "DCAOT") Ownable(msg.sender) {}

    /// @notice Mints a new order token.
    /// @param to The address that will own the minted token.
    /// @param tokenId The token ID of the minted token.
    /// @param order The order data associated with the token.
    function mint(address to, uint256 tokenId, DCAOrderLib.DCAOrder calldata order) external onlyOwner {
        _safeMint(to, tokenId);
        orders[tokenId] = order;
    }

    /// @notice Burns an existing order token.
    /// @param tokenId The token ID of the token to burn.
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        delete orders[tokenId];
    }

    /// @notice Updates the order data associated with a token.
    /// @param tokenId The token ID of the token to update.
    /// @param order The new order data.
    function updateOrder(uint256 tokenId, DCAOrderLib.DCAOrder calldata order) external onlyOwner {
        if (_ownerOf(tokenId) == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        orders[tokenId] = order;
    }

    /// @notice Returns the order data associated with a token.
    /// @param tokenId The token ID of the token.
    /// @return The order data.
    function getOrder(uint256 tokenId) external view returns (DCAOrderLib.DCAOrder memory) {
        return orders[tokenId];
    }
}
