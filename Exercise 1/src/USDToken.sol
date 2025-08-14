// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title USDToken
 * @notice A simple ERC20 token representing USD that can be minted by anyone
 * @dev This token serves as the underlying asset for the redeemable vault system
 */
contract USDToken is ERC20, Ownable {
    
    /// @notice Event emitted when tokens are minted
    event TokensMinted(address indexed to, uint256 amount);

    /**
     * @notice Constructor initializes the token with name and symbol
     */
    constructor() ERC20("USD Token", "USD") Ownable(msg.sender) {
        // No initial supply minted, users must mint as needed
    }

    /**
     * @notice Allows anyone to mint USD tokens
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint (in wei, 18 decimals)
     */
    function mint(address to, uint256 amount) public {
        require(to != address(0), "Can not mint to zero address");
        require(amount > 0, "Mint amount must be positive");
        
        // OpenZeppelin _mint handles the minting logic
        _mint(to, amount);
        
        emit TokensMinted(to, amount);
    }

    /**
     * @notice Convenience function for users to mint tokens to themselves
     * @param amount Amount of tokens to mint to msg.sender
     */
    function mintToSelf(uint256 amount) external {
        mint(msg.sender, amount);
    }

    /**
     * @notice Returns the number of decimals used by the token
     * @return Number of decimals (18, standard for most ERC20 tokens)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Get the total supply in a human-readable format
     * @return Total supply divided by 10^18 for easier reading
     */
    function totalSupplyFormatted() external view returns (uint256) {
        return totalSupply() / 1e18;
    }

    /**
     * @notice Get balance in human-readable format
     * @param account Address to check balance for
     * @return Balance divided by 10^18 for easier reading
     */
    function balanceOfFormatted(address account) external view returns (uint256) {
        return balanceOf(account) / 1e18;
    }
}