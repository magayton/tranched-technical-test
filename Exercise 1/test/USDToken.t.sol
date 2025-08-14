// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/USDToken.sol";

contract USDTokenTest is Test {
    USDToken public usdToken;
    
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    uint256 constant MINT_AMOUNT = 1000e18;
    uint256 constant LARGE_AMOUNT = 1e24; // 1 million tokens
    string constant TOKEN_NAME = "USD Token";
    string constant TOKEN_SYMBOL = "USD";
    
    event TokensMinted(address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    function setUp() public {
        // Deploy USDToken
        usdToken = new USDToken();
        
        // Verify initial state
        assertEq(usdToken.name(), TOKEN_NAME);
        assertEq(usdToken.symbol(), TOKEN_SYMBOL);
        assertEq(usdToken.decimals(), 18);
        assertEq(usdToken.totalSupply(), 0);
    }
    
    /**
     * @notice Test initial deployment state
     */
    function test_InitialState() view public {
        assertEq(usdToken.name(), TOKEN_NAME);
        assertEq(usdToken.symbol(), TOKEN_SYMBOL);
        assertEq(usdToken.decimals(), 18);
        assertEq(usdToken.totalSupply(), 0);
        assertEq(usdToken.balanceOf(user1), 0);
        assertEq(usdToken.balanceOf(user2), 0);
    }
    
    /**
     * @notice Test basic public minting functionality
     */
    function test_PublicMint() public {
        // Mint tokens to user1
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, MINT_AMOUNT);
        
        usdToken.mint(user1, MINT_AMOUNT);
        
        // Verify state changes
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT);
        assertEq(usdToken.totalSupply(), MINT_AMOUNT);
        
        // Test minting to user2
        usdToken.mint(user2, MINT_AMOUNT * 2);
        
        assertEq(usdToken.balanceOf(user2), MINT_AMOUNT * 2);
        assertEq(usdToken.totalSupply(), MINT_AMOUNT * 3);
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT); // user1 balance unchanged
    }
    
    /**
     * @notice Test mintToSelf functionality
     */
    function test_MintToSelf() public {
        vm.startPrank(user1);
        
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, MINT_AMOUNT);
        
        usdToken.mintToSelf(MINT_AMOUNT);
        
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT);
        assertEq(usdToken.totalSupply(), MINT_AMOUNT);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test that anybody can mint
     */
    function test_AnyoneCanMint() public {
        // user1 mints
        vm.startPrank(user1);
        usdToken.mint(user1, MINT_AMOUNT);
        vm.stopPrank();
        
        // user2 mints
        vm.startPrank(user2);
        usdToken.mint(user2, MINT_AMOUNT);
        vm.stopPrank();
        
        // user3 mints to user1
        vm.startPrank(user3);
        usdToken.mint(user1, MINT_AMOUNT);
        vm.stopPrank();
        
        // Verify all mints worked
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT * 2);
        assertEq(usdToken.balanceOf(user2), MINT_AMOUNT);
        assertEq(usdToken.totalSupply(), MINT_AMOUNT * 3);
    }
    
    /**
     * @notice Test minting to zero address fails
     */
    function test_MintToZeroAddressFails() public {
        vm.expectRevert("Can not mint to zero address");
        usdToken.mint(address(0), MINT_AMOUNT);
    }
    
    /**
     * @notice Test minting zero amount fails
     */
    function test_MintZeroAmountFails() public {
        vm.expectRevert("Mint amount must be positive");
        usdToken.mint(user1, 0);
        
        vm.startPrank(user1);
        vm.expectRevert("Mint amount must be positive");
        usdToken.mintToSelf(0);
        vm.stopPrank();
    }
    
    /**
     * @notice Test minting large amounts
     */
    function test_MintLargeAmounts() public {
        usdToken.mint(user1, LARGE_AMOUNT);
        
        assertEq(usdToken.balanceOf(user1), LARGE_AMOUNT);
        assertEq(usdToken.totalSupply(), LARGE_AMOUNT);
        
        // Test multiple large mints
        usdToken.mint(user2, LARGE_AMOUNT * 2);
        assertEq(usdToken.totalSupply(), LARGE_AMOUNT * 3);
    }
    
    /**
     * @notice Test minting very large amounts works within limits
     */
    function test_LargeAmountMinting() public {
        uint256 largeAmount = 1e30; // 1 billion tokens with 18 decimals
        
        usdToken.mint(user1, largeAmount);
        assertEq(usdToken.balanceOf(user1), largeAmount);
        assertEq(usdToken.totalSupply(), largeAmount);
        
        // Test multiple large mints
        usdToken.mint(user2, largeAmount);
        assertEq(usdToken.totalSupply(), largeAmount * 2);
    }
    
    /**
     * @notice Test all events are emitted correctly
     */
    function test_EventEmission() public {
        // Test TokensMinted event
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user1, MINT_AMOUNT);
        usdToken.mint(user1, MINT_AMOUNT);
        
        // Test Transfer event (from ERC20)
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, MINT_AMOUNT);
        usdToken.mint(user1, MINT_AMOUNT);
        
        // Test mintToSelf events
        vm.startPrank(user2);
        vm.expectEmit(true, false, false, true);
        emit TokensMinted(user2, MINT_AMOUNT);
        usdToken.mintToSelf(MINT_AMOUNT);
        vm.stopPrank();
    }
    
    /**
     * @notice Test formatted balance functions
     */
    function test_FormattedFunctions() public {
        uint256 amount = 1500e18; // 1500 tokens
        usdToken.mint(user1, amount);
        
        // Test totalSupplyFormatted
        assertEq(usdToken.totalSupplyFormatted(), 1500);
        
        // Test balanceOfFormatted
        assertEq(usdToken.balanceOfFormatted(user1), 1500);
        assertEq(usdToken.balanceOfFormatted(user2), 0);
        
        // Test with fractional amounts
        uint256 fractionalAmount = 1500.5e18; // 1500.5 tokens
        usdToken.mint(user2, fractionalAmount);
        
        // Should truncate decimal part
        assertEq(usdToken.balanceOfFormatted(user2), 1500);
    }
    
    /**
     * @notice Test standard ERC20 transfers work correctly
     */
    function test_StandardTransfers() public {
        // Mint tokens to user1
        usdToken.mint(user1, MINT_AMOUNT);
        
        // Test transfer
        vm.startPrank(user1);
        usdToken.transfer(user2, MINT_AMOUNT / 2);
        vm.stopPrank();
        
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT / 2);
        assertEq(usdToken.balanceOf(user2), MINT_AMOUNT / 2);
        assertEq(usdToken.totalSupply(), MINT_AMOUNT);
    }
    
    /**
     * @notice Test standard ERC20 approvals work correctly
     */
    function test_StandardApprovals() public {
        usdToken.mint(user1, MINT_AMOUNT);
        
        // Test approval
        vm.startPrank(user1);
        usdToken.approve(user2, MINT_AMOUNT / 2);
        vm.stopPrank();
        
        assertEq(usdToken.allowance(user1, user2), MINT_AMOUNT / 2);
        
        // Test transferFrom
        vm.startPrank(user2);
        usdToken.transferFrom(user1, user3, MINT_AMOUNT / 4);
        vm.stopPrank();
        
        assertEq(usdToken.balanceOf(user1), MINT_AMOUNT - MINT_AMOUNT / 4);
        assertEq(usdToken.balanceOf(user3), MINT_AMOUNT / 4);
        assertEq(usdToken.allowance(user1, user2), MINT_AMOUNT / 4);
    }
    
    /**
     * @notice Test multiple users minting and interacting
     */
    function test_MultiUserScenario() public {
        // Multiple users mint different amounts
        vm.startPrank(user1);
        usdToken.mintToSelf(1000e18);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdToken.mint(user2, 2000e18);
        vm.stopPrank();
        
        vm.startPrank(user3);
        usdToken.mint(user1, 500e18); // user3 mints to user1
        vm.stopPrank();
        
        // Verify final state
        assertEq(usdToken.balanceOf(user1), 1500e18); // 1000 + 500
        assertEq(usdToken.balanceOf(user2), 2000e18);
        assertEq(usdToken.balanceOf(user3), 0);
        assertEq(usdToken.totalSupply(), 3500e18);
        
        // Test transfers between users
        vm.startPrank(user1);
        usdToken.transfer(user2, 200e18);
        vm.stopPrank();
        
        assertEq(usdToken.balanceOf(user1), 1300e18);
        assertEq(usdToken.balanceOf(user2), 2200e18);
    }
    
    // ============ FUZZ TESTS ============
    
    /**
     * @notice Fuzz test minting with random amounts and addresses
     */
    function testFuzz_Mint(address to, uint256 amount) public {
        // Skip zero address and zero amount (expected to fail)
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(amount < type(uint128).max); // Avoid overflow issues
        
        uint256 balanceBefore = usdToken.balanceOf(to);
        uint256 totalSupplyBefore = usdToken.totalSupply();
        
        usdToken.mint(to, amount);
        
        assertEq(usdToken.balanceOf(to), balanceBefore + amount);
        assertEq(usdToken.totalSupply(), totalSupplyBefore + amount);
    }
    
    /**
     * @notice Test minting 1 wei (smallest possible amount)
     */
    function test_MintOneWei() public {
        usdToken.mint(user1, 1);
        
        assertEq(usdToken.balanceOf(user1), 1);
        assertEq(usdToken.totalSupply(), 1);
        assertEq(usdToken.balanceOfFormatted(user1), 0); // Should be 0 when formatted
    }
    
    /**
     * @notice Test multiple small mints accumulate correctly
     */
    function test_MultipleSmallMints() public {
        for (uint256 i = 1; i <= 100; i++) {
            usdToken.mint(user1, i);
        }
        
        // Sum of 1+2+...+100
        assertEq(usdToken.balanceOf(user1), 5050);
        assertEq(usdToken.totalSupply(), 5050);
    }
    
    /**
     * @notice Test contract behavior with many users
     */
    function test_ManyUsers() public {
        address[] memory users = new address[](10);
        
        // Create and mint to many users
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            usdToken.mint(users[i], (i + 1) * 100e18);
        }
        
        // Verify user's balance
        for (uint256 i = 0; i < 10; i++) {
            assertEq(usdToken.balanceOf(users[i]), (i + 1) * 100e18);
        }
        
        // Verify total supply (sum of 1+2+...+10)*100e18 = 55*100e18
        assertEq(usdToken.totalSupply(), 5500e18);
    }
}