// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Pool.sol";
import "../src/USDToken.sol";

/**
 * @title PoolTest
 * @notice Test suite for the redeemable vault Pool contract
 */
contract PoolTest is Test {
    
    Pool public pool;
    USDToken public usdToken;
    
    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public attacker = makeAddr("attacker");
    
    uint256 constant INITIAL_MINT = 1000000e18; // 1M USD tokens for each user
    uint256 constant DEPOSIT_AMOUNT = 1000e18;  // 1k USD deposit
    uint256 constant PROCEEDS_AMOUNT = 100e18;  // 100 USD proceeds

    string constant POOL_NAME = "Pool USD Token";
    string constant POOL_SYMBOL = "pUSD";
    uint256 constant PRECISION = 1e18;
    
    event Deposit(address indexed user, uint256 usdAmount, uint256 poolTokensMinted);
    event Withdrawal(address indexed user, uint256 poolTokensBurned, uint256 usdReceived);
    event ProceedsDeposited(address indexed admin, uint256 amount, uint256 newCumulativeRewardsPerShare);
    event ProceedsClaimed(address indexed user, uint256 amount);
    event ZeroSupplyProceedsDistributed(address indexed firstDepositor, uint256 amount);
    
    function setUp() public {
        // Deploy USD token
        usdToken = new USDToken();
        
        // Deploy Pool implementation
        pool = new Pool();
        
        // Initialize pool with admin
        pool.initialize(address(usdToken), admin, POOL_NAME, POOL_SYMBOL);
        
        // Verify initial state
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        assertEq(address(pool.usdToken()), address(usdToken));
        assertEq(pool.owner(), admin);
        assertEq(pool.totalSupply(), 0);
        assertEq(pool.cumulativeRewardsPerShare(), 0);
        assertEq(pool.totalProceedsDeposited(), 0);
        assertEq(pool.pendingProceedsForZeroSupply(), 0);
        
        // Setup test users with USD tokens and approvals
        _setupTestUsers();
    }
    
    function _setupTestUsers() internal {
        address[4] memory users = [user1, user2, user3, attacker];
        
        for (uint256 i = 0; i < users.length; i++) {
            // Mint USD tokens to users
            usdToken.mint(users[i], INITIAL_MINT);
            
            // Approve pool to spend USD tokens
            vm.startPrank(users[i]);
            usdToken.approve(address(pool), type(uint256).max);
            vm.stopPrank();
        }
        
        // Give admin USD tokens for proceeds
        usdToken.mint(admin, INITIAL_MINT);
        vm.startPrank(admin);
        usdToken.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }
    
    /**
     * @notice Test initial deployment and initialization
     */
    function test_Initialization() view public {
        assertEq(pool.name(), POOL_NAME);
        assertEq(pool.symbol(), POOL_SYMBOL);
        assertEq(pool.decimals(), 18);
        assertEq(address(pool.usdToken()), address(usdToken));
        assertEq(pool.owner(), admin);
        assertEq(pool.totalSupply(), 0);
        assertEq(pool.cumulativeRewardsPerShare(), 0);
        assertEq(pool.totalProceedsDeposited(), 0);
        assertEq(pool.pendingProceedsForZeroSupply(), 0);
        
        // Check that all users start with zero proceeds and checkpoints
        for (uint256 i = 0; i < 4; i++) {
            address user = [user1, user2, user3, attacker][i];
            assertEq(pool.getPendingProceeds(user), 0);
            assertEq(pool.lastRewardPerShare(user), 0);
            assertEq(pool.lockedProceeds(user), 0);
        }
    }
    
    /**
     * @notice Test that initialize can only be called once
     */
    function test_InitializeOnlyOnce() public {
        vm.expectRevert();
        pool.initialize(address(usdToken), admin, "New Name", "NEW");
    }
    
    /**
     * @notice Test initialization with invalid parameters
     */
    function test_InitializationValidation() public {
        Pool newPool = new Pool();
        
        // Test zero USD token address
        vm.expectRevert(Pool.ZeroAddress.selector);
        newPool.initialize(address(0), admin, POOL_NAME, POOL_SYMBOL);
        
        // Test zero admin address  
        vm.expectRevert(Pool.ZeroAddress.selector);
        newPool.initialize(address(usdToken), address(0), POOL_NAME, POOL_SYMBOL);
    }
    
    /**
     * @notice Test basic deposit functionality and 1:1 conversion requirement
     */
    function test_BasicDeposit() public {
        vm.startPrank(user1);
        
        uint256 balanceBefore = usdToken.balanceOf(user1);
        uint256 poolBalanceBefore = usdToken.balanceOf(address(pool));
        
        // Expect events
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        
        pool.deposit(DEPOSIT_AMOUNT);
        
        // Verify 1:1 conversion requirement
        assertEq(pool.balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(pool.totalSupply(), DEPOSIT_AMOUNT);
        assertEq(usdToken.balanceOf(user1), balanceBefore - DEPOSIT_AMOUNT);
        assertEq(usdToken.balanceOf(address(pool)), poolBalanceBefore + DEPOSIT_AMOUNT);
        
        // Verify user starts fresh (no retroactive proceeds)
        assertEq(pool.lastRewardPerShare(user1), 0); 
        assertEq(pool.getPendingProceeds(user1), 0);
        assertEq(pool.lockedProceeds(user1), 0);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test multiple user deposits and proportional tracking
     */
    function test_MultipleUserDeposits() public {
        // User1 deposits
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // User2 deposits different amount
        vm.startPrank(user2);
        pool.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // Verify individual and total state
        assertEq(pool.balanceOf(user1), DEPOSIT_AMOUNT);
        assertEq(pool.balanceOf(user2), DEPOSIT_AMOUNT * 2);
        assertEq(pool.totalSupply(), DEPOSIT_AMOUNT * 3);
        assertEq(usdToken.balanceOf(address(pool)), DEPOSIT_AMOUNT * 3);
        
        // Both users should start fresh
        assertEq(pool.lastRewardPerShare(user1), 0);
        assertEq(pool.lastRewardPerShare(user2), 0);
        assertEq(pool.getPendingProceeds(user1), 0);
        assertEq(pool.getPendingProceeds(user2), 0);
    }
    
    /**
     * @notice Test deposit input validation
     */
    function test_DepositValidation() public {
        vm.startPrank(user1);
        
        // Test zero amount deposit
        vm.expectRevert(Pool.ZeroAmount.selector);
        pool.deposit(0);
        
        // Test insufficient USD balance
        vm.expectRevert();
        pool.deposit(INITIAL_MINT + 1);
        
        // Test insufficient allowance
        usdToken.approve(address(pool), DEPOSIT_AMOUNT - 1);
        vm.expectRevert();
        pool.deposit(DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test basic withdrawal functionality and 1:1 conversion
     */
    function test_BasicWithdrawal() public {
        // Setup: User deposits first
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user1, withdrawAmount, withdrawAmount);
        
        pool.withdraw(withdrawAmount);
        
        // Verify 1:1 conversion maintained
        assertEq(pool.balanceOf(user1), DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(pool.totalSupply(), DEPOSIT_AMOUNT - withdrawAmount);
        assertEq(usdToken.balanceOf(user1), balanceBefore + withdrawAmount);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test withdrawal with proceeds (force claim requirement)
     */
    function test_WithdrawalWithProceedsForcesClaim() public {
        // User deposits
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Admin deposits proceeds
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // User withdraws - should auto claim proceeds
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        uint256 pendingProceeds = pool.getPendingProceeds(user1);
        assertEq(pendingProceeds, PROCEEDS_AMOUNT); // Should get all proceeds (100% pool)
        
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        
        // Expect proceeds claimed event
        vm.expectEmit(true, false, false, true);
        emit ProceedsClaimed(user1, pendingProceeds);
        
        pool.withdraw(withdrawAmount);
        
        // Should receive withdrawal amount + all proceeds 
        uint256 expectedReceived = withdrawAmount + pendingProceeds;
        assertEq(usdToken.balanceOf(user1), balanceBefore + expectedReceived);
        
        // Must have zero outstanding proceeds after withdrawal
        assertEq(pool.getPendingProceeds(user1), 0);
        assertEq(pool.lockedProceeds(user1), 0);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test withdrawal validation
     */
    function test_WithdrawalValidation() public {
        vm.startPrank(user1);
        
        // Test zero amount withdrawal
        vm.expectRevert(Pool.ZeroAmount.selector);
        pool.withdraw(0);
        
        // Test insufficient balance
        vm.expectRevert(Pool.InsufficientBalance.selector);
        pool.withdraw(1);
        
        // Setup some balance
        pool.deposit(DEPOSIT_AMOUNT);
        
        // Test withdrawing more than balance
        vm.expectRevert(Pool.InsufficientBalance.selector);
        pool.withdraw(DEPOSIT_AMOUNT + 1);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test basic proceeds deposit and cumulative rewards calculation
     */
    function test_BasicProceedsDeposit() public {
        // Users deposit first
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Admin deposits proceeds
        vm.startPrank(admin);
        uint256 totalSupply = DEPOSIT_AMOUNT * 2;
        uint256 expectedRewardsPerShare = (PROCEEDS_AMOUNT * PRECISION) / totalSupply;
        
        vm.expectEmit(true, false, false, true);
        emit ProceedsDeposited(admin, PROCEEDS_AMOUNT, expectedRewardsPerShare);
        
        pool.depositProceeds(PROCEEDS_AMOUNT);
        
        // Verify state updates
        assertEq(pool.cumulativeRewardsPerShare(), expectedRewardsPerShare);
        assertEq(pool.totalProceedsDeposited(), PROCEEDS_AMOUNT);
        assertEq(usdToken.balanceOf(address(pool)), totalSupply + PROCEEDS_AMOUNT);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test proceeds distribution calculation accuracy
     */
    function test_ProceedsDistributionCalculation() public {
        // User1 deposits 1000, User2 deposits 2000 (33.33% and 66.67% ownership)
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user2);
        pool.deposit(DEPOSIT_AMOUNT * 2);
        vm.stopPrank();
        
        // Total supply: 3000, Proceeds: 300
        uint256 proceeds = 300e18;
        
        vm.startPrank(admin);
        pool.depositProceeds(proceeds);
        vm.stopPrank();
        
        // Verify proportional distribution base on relative share
        uint256 expectedUser1 = proceeds / 3;      // 100 USD (33.33%)
        uint256 expectedUser2 = proceeds * 2 / 3;  // 200 USD (66.67%)
        
        assertEq(pool.getPendingProceeds(user1), expectedUser1);
        assertEq(pool.getPendingProceeds(user2), expectedUser2);
    }
    
    /**
     * @notice Test proceeds deposit access control
     */
    function test_ProceedsDepositAccessControl() public {
        // Non-admin cannot deposit proceeds
        vm.startPrank(user1);
        vm.expectRevert();
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
    }
    
    /**
     * @notice Test zero supply proceeds edge case handling
     */
    function test_ZeroSupplyProceedsHandling() public {
        // Deposit proceeds when no one has deposited yet
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // Should be stored for first depositor (can't divide by zero)
        assertEq(pool.pendingProceedsForZeroSupply(), PROCEEDS_AMOUNT);
        assertEq(pool.cumulativeRewardsPerShare(), 0);
        
        // First depositor should get the stored proceeds
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        
        vm.expectEmit(true, false, false, true);
        emit ZeroSupplyProceedsDistributed(user1, PROCEEDS_AMOUNT);
        
        pool.deposit(DEPOSIT_AMOUNT);
        
        // Should receive deposit back + proceeds
        uint256 expectedBalance = balanceBefore - DEPOSIT_AMOUNT + PROCEEDS_AMOUNT;
        assertEq(usdToken.balanceOf(user1), expectedBalance);
        assertEq(pool.pendingProceedsForZeroSupply(), 0); // Cleared after distribution
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test manual proceeds claiming functionality
     */
    function test_ManualProceedsClaiming() public {
        // Setup
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // User claims proceeds manually
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        uint256 pendingBefore = pool.getPendingProceeds(user1);
        assertEq(pendingBefore, PROCEEDS_AMOUNT); // 100% ownership
        
        vm.expectEmit(true, false, false, true);
        emit ProceedsClaimed(user1, pendingBefore);
        
        pool.claimProceeds();
        
        // Verify proceeds claimed
        assertEq(usdToken.balanceOf(user1), balanceBefore + pendingBefore);
        assertEq(pool.getPendingProceeds(user1), 0);
        assertEq(pool.lastRewardPerShare(user1), pool.cumulativeRewardsPerShare());
        assertEq(pool.lockedProceeds(user1), 0);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test claiming when no proceeds available
     */
    function test_ClaimNoProceedsAvailable() public {
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        
        uint256 balanceBefore = usdToken.balanceOf(user1);
        
        // Should not revert, but no transfer should occur
        pool.claimProceeds();
        
        assertEq(usdToken.balanceOf(user1), balanceBefore);
        assertEq(pool.getPendingProceeds(user1), 0);
        
        vm.stopPrank();
    }
    
    /**
    * @notice Test the pool token transfer behavior
    */
    function test_TransferPoolTokens() public {
        // Setup: Both users deposit initially
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT); // User1: 1000e18 tokens
        vm.stopPrank();
        
        vm.startPrank(user2);
        pool.deposit(DEPOSIT_AMOUNT / 2); // User2: 500e18 tokens  
        vm.stopPrank();
        
        // Total supply: 1500e18, User1: 66.67%, User2: 33.33%
        
        // First proceeds distribution
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT); // 100e18 USD
        vm.stopPrank();
        
        // Check initial proceeds distribution
        uint256 user1InitialProceeds = pool.getPendingProceeds(user1); // ~66.67 USD
        uint256 user2InitialProceeds = pool.getPendingProceeds(user2); // ~33.33 USD
        
        assertApproxEqAbs(user1InitialProceeds, (PROCEEDS_AMOUNT * 2) / 3, 1e15); // 66.67 USD
        assertApproxEqAbs(user2InitialProceeds, PROCEEDS_AMOUNT / 3, 1e15); // 33.33 USD
        
        // Record User2's USD balance before transfer
        uint256 user2USDBalanceBefore = usdToken.balanceOf(user2);
        
        // User1 transfers tokens to User2
        // User2 should not lose its existing 33.33 USD proceeds
        vm.startPrank(user1);
        pool.transfer(user2, DEPOSIT_AMOUNT / 2); // Transfer 500e18 tokens
        vm.stopPrank();
        
        // Check User2's USD balance after transfer
        uint256 user2USDBalanceAfter = usdToken.balanceOf(user2);
        
        // User2 should have auto-claimed their existing proceeds (based on old balance)
        uint256 user2ClaimedAmount = user2USDBalanceAfter - user2USDBalanceBefore;
        assertApproxEqAbs(user2ClaimedAmount, user2InitialProceeds, 1e15); // Should have received exactly their original ~33.33 USD
        
        // After transfer state checks
        // User1 should keep full historical proceeds locked
        assertApproxEqAbs(pool.getPendingProceeds(user1), user1InitialProceeds, 1e15); // Still ~66.67 USD
        assertApproxEqAbs(pool.lockedProceeds(user1), user1InitialProceeds, 1e15); // Locked ~66.67 USD
        
        // User2 should start fresh with no pending proceeds (they were auto-claimed)
        assertEq(pool.getPendingProceeds(user2), 0);
        assertEq(pool.lastRewardPerShare(user2), pool.cumulativeRewardsPerShare());
        assertEq(pool.lockedProceeds(user2), 0);
        
        // Check token balances after transfer
        assertEq(pool.balanceOf(user1), DEPOSIT_AMOUNT / 2); // 500e18 tokens 
        assertEq(pool.balanceOf(user2), DEPOSIT_AMOUNT); // 1000e18 tokens (500 + 500)
        
        // Future proceeds should be split based on new token balances
        // User1: 500 tokens (33.33%), User2: 1000 tokens (66.67%)
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT); // Another 100e18 USD
        vm.stopPrank();
        
        // Calculate expected new proceeds based on current balances
        uint256 user1NewProceeds = PROCEEDS_AMOUNT / 3; // 33.33 USD
        uint256 user2NewProceeds = (PROCEEDS_AMOUNT * 2) / 3; // 66.67 USD 
        
        // User1 : Historical locked proceeds + new proceeds
        uint256 expectedUser1Total = user1InitialProceeds + user1NewProceeds; // ~66.67 + 33.33 = 100 USD
        
        // User2 : Only new proceeds (historical were auto claimed during transfer)
        uint256 expectedUser2Total = user2NewProceeds; // ~66.67 USD
        
        assertApproxEqAbs(pool.getPendingProceeds(user1), expectedUser1Total, 1e15);
        assertApproxEqAbs(pool.getPendingProceeds(user2), expectedUser2Total, 1e15);
        
        // Verify User2 can claim their new proceeds
        vm.startPrank(user2);
        pool.claimProceeds();
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user2), 0);
        
        // Verify User1 can still claim their full accumulated proceeds
        uint256 user1USDBalanceBefore = usdToken.balanceOf(user1);
        vm.startPrank(user1);
        pool.claimProceeds();
        vm.stopPrank();
        
        uint256 user1USDBalanceAfter = usdToken.balanceOf(user1);
        uint256 user1ClaimedAmount = user1USDBalanceAfter - user1USDBalanceBefore;
        
        assertApproxEqAbs(user1ClaimedAmount, expectedUser1Total, 1e15);
        assertEq(pool.getPendingProceeds(user1), 0);
    }
    
    /**
     * @notice Test that locked proceeds are claimed correctly
     */
    function test_LockedProceedsClaiming() public {
        // Setup: User1 deposits, gets proceeds, transfers tokens
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(user1);
        pool.transfer(user2, DEPOSIT_AMOUNT / 2); // locks proceeds
        vm.stopPrank();
        
        // Verify locked proceeds state
        assertEq(pool.lockedProceeds(user1), PROCEEDS_AMOUNT);
        assertEq(pool.getPendingProceeds(user1), PROCEEDS_AMOUNT);
        
        // User1 claims all proceeds (locked + any new)
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        
        vm.expectEmit(true, false, false, true);
        emit ProceedsClaimed(user1, PROCEEDS_AMOUNT);
        
        pool.claimProceeds();
        
        // Should receive all locked proceeds
        assertEq(usdToken.balanceOf(user1), balanceBefore + PROCEEDS_AMOUNT);
        assertEq(pool.getPendingProceeds(user1), 0);
        assertEq(pool.lockedProceeds(user1), 0); // Cleared after claim
        
        vm.stopPrank();
    }
    
    /**
     * @notice Test multiple transfers accumulate locked proceeds correctly
     */
    function test_MultipleTransfersAccumulateLockedProceeds() public {
        // User1 deposits and accumulates proceeds
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT); // 100 USD
        vm.stopPrank();
        
        // First transfer: locks 100 USD
        // But they are auto claimed
        vm.startPrank(user1);
        pool.transfer(user2, DEPOSIT_AMOUNT / 4); // Transfer 25%
        vm.stopPrank();
        
        assertEq(pool.lockedProceeds(user1), PROCEEDS_AMOUNT);
        
        // More proceeds deposited
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT); // Another 100 USD
        vm.stopPrank();
        
        // User1 should have 175 (PROCEEDS_AMOUNT from first deposit + 75 from second deposit)
        assertEq(pool.getPendingProceeds(user1), PROCEEDS_AMOUNT + 75e18);
        
        // Second transfer: should add current proceeds to locked
        vm.startPrank(user1);
        pool.transfer(user3, DEPOSIT_AMOUNT / 4); // Transfer another 25%
        vm.stopPrank();
        
        // Should now have 175 USD locked (100 + 75)
        assertEq(pool.lockedProceeds(user1), 175e18);
    }

    /**
    * @notice Test second deposit preserves proceeds after auto-claim
    */
    function test_SecondDepositPreservesProceeds() public {
        // STEP 1: User deposits and earns proceeds
        vm.startPrank(user1);
        pool.deposit(1000e18); // 1000 USD → 1000 pool tokens
        vm.stopPrank();
        
        // Admin deposits proceeds
        vm.startPrank(admin);
        pool.depositProceeds(100e18); // 100 USD proceeds
        vm.stopPrank();
        
        // User1 should have 100% of proceeds (only depositor)
        uint256 proceedsBeforeSecondDeposit = pool.getPendingProceeds(user1);
        assertEq(proceedsBeforeSecondDeposit, 100e18); // User1 gets all 100 USD
        
        // STEP 2: Record state before second deposit 
        uint256 usdBalanceBefore = usdToken.balanceOf(user1);
        uint256 poolBalanceBefore = pool.balanceOf(user1);
        
        // STEP 3: User makes second deposit
        vm.startPrank(user1);
        pool.deposit(500e18); // Second deposit: 500 USD → 500 pool tokens
        vm.stopPrank();
        
        // STEP 4: Verify proceeds were preserved (auto claimed)
        uint256 usdBalanceAfter = usdToken.balanceOf(user1);
        uint256 poolBalanceAfter = pool.balanceOf(user1);
        uint256 proceedsAfterSecondDeposit = pool.getPendingProceeds(user1);
        
        // 1. Pool tokens increased correctly
        assertEq(poolBalanceAfter, poolBalanceBefore + 500e18); // 1000 + 500 = 1500 tokens
        
        // 2. Pending proceeds were reset (auto claimed)
        assertEq(proceedsAfterSecondDeposit, 0); // Must be 0 after auto-claim

        // 3. User's USD balance should reflect proceeds claim
        int256 expectedNetChange = 100e18; // Proceeds claimed
        uint256 depositAmount = 500e18; // Amount deposited
        
        // Calculate actual USD change (can be negative)
        int256 actualUSDChange = int256(usdBalanceAfter) - int256(usdBalanceBefore);
        int256 expectedUSDChange = int256(expectedNetChange) - int256(depositAmount); // 100 - 500 = -400
        
        assertEq(actualUSDChange, expectedUSDChange); // Should be -400 USD
    }
    
    /**
     * @notice Test complex multi-user scenario
     */
    function test_ComplexMultiUserTimeWeightedScenario() public {
        // Day 1: User1 deposits (100% ownership)
        vm.startPrank(user1);
        pool.deposit(1000e18);
        vm.stopPrank();
        
        // Day 2: First proceeds deposit (User1 gets 100% since they own 100% "at that time")
        vm.startPrank(admin);
        pool.depositProceeds(100e18);
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user1), 100e18); // Gets all proceeds
        assertEq(pool.getPendingProceeds(user2), 0);      // Not in pool yet
        
        // Day 3: User2 joins (should not get retroactive proceeds)
        vm.startPrank(user2);
        pool.deposit(2000e18);
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user1), 100e18); // Still has all first proceeds
        assertEq(pool.getPendingProceeds(user2), 0);      // No retroactive proceeds
        
        // Day 4: Second proceeds deposit (should split based on "relative share at that time")
        // User1: 1000/3000 = 33.33%, User2: 2000/3000 = 66.67%
        vm.startPrank(admin);
        pool.depositProceeds(150e18);
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user1), 100e18 + 50e18);  // 100 old + 50 new (33.33%)
        assertEq(pool.getPendingProceeds(user2), 100e18);          // 0 old + 100 new (66.67%)
        
        // Day 5: User3 joins (should not get retroactive proceeds)
        vm.startPrank(user3);
        pool.deposit(3000e18);
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user3), 0); // No retroactive proceeds
        
        // Day 6: Third proceeds deposit (split between all three based on current ownership)
        // Total supply: 6000, so 1000 tokens = 16.67%, 2000 = 33.33%, 3000 = 50%
        vm.startPrank(admin);
        pool.depositProceeds(300e18);
        vm.stopPrank();
        
        assertEq(pool.getPendingProceeds(user1), 150e18 + 50e18);   // Previous + 50 new
        assertEq(pool.getPendingProceeds(user2), 100e18 + 100e18);  // Previous + 100 new
        assertEq(pool.getPendingProceeds(user3), 150e18);           // Only new
        
        // Verify total proceeds distributed equals total deposited
        uint256 totalUserProceeds = pool.getPendingProceeds(user1) + 
                                   pool.getPendingProceeds(user2) + 
                                   pool.getPendingProceeds(user3);
        assertEq(totalUserProceeds, 550e18); // 100 + 150 + 300
    }
    
    /**
     * @notice Test late joiner attack prevention
     */
    function test_LateJoinerAttackPrevention() public {
        // Setup : User1 is long-term holder
        vm.startPrank(user1);
        pool.deposit(1000e18);
        vm.stopPrank();
        
        // Multiple proceeds over time (User1 should get all)
        vm.startPrank(admin);
        pool.depositProceeds(100e18);
        pool.depositProceeds(100e18);
        pool.depositProceeds(100e18);
        vm.stopPrank();
        
        uint256 user1AccumulatedProceeds = pool.getPendingProceeds(user1);
        assertEq(user1AccumulatedProceeds, 300e18); // All historical proceeds
        
        // Attacker tries to join right before another proceeds deposit
        vm.startPrank(attacker);
        pool.deposit(1000e18); // Same amount as user1
        vm.stopPrank();
        
        // Attacker should have 0 pending proceeds (no retroactive benefits)
        assertEq(pool.getPendingProceeds(attacker), 0);
        
        // New proceeds deposit
        vm.startPrank(admin);
        pool.depositProceeds(200e18);
        vm.stopPrank();
        
        // Should split 50/50 going forward, but user1 keeps historical proceeds
        assertEq(pool.getPendingProceeds(user1), 300e18 + 100e18);  // Historical + new
        assertEq(pool.getPendingProceeds(attacker), 100e18);        // Only new proceeds
    }
    
    /**
     * @notice Test getPendingProceeds calculation accuracy with locked proceeds
     */
    function test_GetPendingProceedsCalculationWithLocked() public {
        // Setup : User1 deposits, gets proceeds, transfers
        vm.startPrank(user1);
        pool.deposit(1000e18);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(100e18);
        vm.stopPrank();
        
        // Transfer to lock proceeds
        vm.startPrank(user1);
        pool.transfer(user2, 500e18);
        vm.stopPrank();
        
        // Verify locked proceeds calculation
        assertEq(pool.getPendingProceeds(user1), 100e18); // All locked
        assertEq(pool.lockedProceeds(user1), 100e18);
        
        // Add new proceeds
        vm.startPrank(admin);
        pool.depositProceeds(100e18);
        vm.stopPrank();
        
        // Should be: 100 locked + 50 new = 150 total
        assertEq(pool.getPendingProceeds(user1), 150e18);
        assertEq(pool.getPendingProceeds(user2), 50e18); // Only new
    }
    
    /**
     * @notice Test contract info view function
     */
    function test_GetContractInfo() public {
        // Setup state
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        (
            uint256 totalSupply_,
            uint256 totalUSDHeld,
            uint256 totalProceeds,
            uint256 pendingForZeroSupply,
            uint256 cumulativeRewards
        ) = pool.getContractInfo();
        
        assertEq(totalSupply_, DEPOSIT_AMOUNT);
        assertEq(totalUSDHeld, DEPOSIT_AMOUNT + PROCEEDS_AMOUNT);
        assertEq(totalProceeds, PROCEEDS_AMOUNT);
        assertEq(pendingForZeroSupply, 0);
        assertGt(cumulativeRewards, 0);
    }
    
    /**
     * @notice Test user info view function with locked proceeds
     */
    function test_GetUserInfoWithLockedProceeds() public {
        // Setup
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // Transfer to create locked proceeds
        vm.startPrank(user1);
        pool.transfer(user2, DEPOSIT_AMOUNT / 2);
        vm.stopPrank();
        
        (
            uint256 poolBalance,
            uint256 pendingProceeds,
            uint256 lastRewardCheckpoint,
            uint256 lockedProceedsAmount
        ) = pool.getUserInfo(user1);
        
        assertEq(poolBalance, DEPOSIT_AMOUNT / 2);
        assertEq(pendingProceeds, PROCEEDS_AMOUNT);
        assertEq(lastRewardCheckpoint, pool.cumulativeRewardsPerShare());
        assertEq(lockedProceedsAmount, PROCEEDS_AMOUNT);
    }
    
    /**
     * @notice Test precision handling with small amounts
     */
    function test_SmallAmountPrecision() public {
        // Test with very small deposits and proceeds
        vm.startPrank(user1);
        pool.deposit(1e6); // 0.000001 tokens
        vm.stopPrank();
        
        vm.startPrank(user2);
        pool.deposit(1e6); // 0.000001 tokens
        vm.stopPrank();
        
        // Small proceeds deposit
        vm.startPrank(admin);
        pool.depositProceeds(2e6); // 0.000002 tokens
        vm.stopPrank();
        
        // Should handle precision correctly with PRECISION scaling
        assertEq(pool.getPendingProceeds(user1), 1e6);
        assertEq(pool.getPendingProceeds(user2), 1e6);
    }
    
    /**
     * @notice Test large amount handling
     */
    function test_LargeAmountHandling() public {
        uint256 largeAmount = 1e30; // Very large amount
        
        // Mint large amounts
        usdToken.mint(user1, largeAmount);
        vm.startPrank(user1);
        usdToken.approve(address(pool), largeAmount);
        pool.deposit(largeAmount);
        vm.stopPrank();
        
        // Large proceeds
        usdToken.mint(admin, largeAmount / 10);
        vm.startPrank(admin);
        usdToken.approve(address(pool), largeAmount / 10);
        pool.depositProceeds(largeAmount / 10);
        vm.stopPrank();
        
        // Should handle correctly without overflow
        assertEq(pool.getPendingProceeds(user1), largeAmount / 10);
    }
    
    /**
     * @notice Test behavior with many small interactions
     */
    function test_ManySmallInteractions() public {
        // Many small deposits
        vm.startPrank(user1);
        for (uint256 i = 1; i <= 10; i++) {
            pool.deposit(i * 1e15); // Small amounts: 0.001, 0.002 ...
        }
        vm.stopPrank();
        
        // Many small proceeds
        vm.startPrank(admin);
        for (uint256 i = 1; i <= 5; i++) {
            pool.depositProceeds(i * 1e15); // Small proceeds
        }
        vm.stopPrank();
        
        // Should handle accumulation correctly
        assertGt(pool.getPendingProceeds(user1), 0);
        assertGt(pool.balanceOf(user1), 0);
    }
    
    /**
     * @notice Fuzz test deposits with random amounts
     */
    function testFuzz_Deposit(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= INITIAL_MINT);
        
        vm.startPrank(user1);
        
        uint256 balanceBefore = usdToken.balanceOf(user1);
        uint256 totalSupplyBefore = pool.totalSupply();
        
        pool.deposit(amount);
        
        // Verify 1:1 conversion
        assertEq(pool.balanceOf(user1), amount);
        assertEq(pool.totalSupply(), totalSupplyBefore + amount);
        assertEq(usdToken.balanceOf(user1), balanceBefore - amount);
        
        vm.stopPrank();
    }
    
    /**
     * @notice Fuzz test proceeds distribution with improved precision handling
     */
    function testFuzz_ProceedsDistribution(uint256 user1Deposit, uint256 user2Deposit, uint256 proceeds) public {
        vm.assume(user1Deposit > 0 && user1Deposit <= INITIAL_MINT / 2);
        vm.assume(user2Deposit > 0 && user2Deposit <= INITIAL_MINT / 2);
        vm.assume(proceeds > 0 && proceeds <= INITIAL_MINT / 2);
        
        // Avoid extreme precision loss scenarios
        uint256 totalSupply = user1Deposit + user2Deposit;
        vm.assume(proceeds >= totalSupply / 1e12); // Proceeds should be reasonable vs total supply
        vm.assume(totalSupply >= proceeds / 1e12);  // Total supply should be reasonable vs proceeds
        
        // Setup deposits
        vm.startPrank(user1);
        pool.deposit(user1Deposit);
        vm.stopPrank();
        
        vm.startPrank(user2);
        pool.deposit(user2Deposit);
        vm.stopPrank();
        
        // Add proceeds
        vm.startPrank(admin);
        pool.depositProceeds(proceeds);
        vm.stopPrank();
        
        // Check proportional distribution
        uint256 expectedUser1 = (proceeds * user1Deposit) / totalSupply;
        uint256 expectedUser2 = (proceeds * user2Deposit) / totalSupply;
        
        uint256 actualUser1 = pool.getPendingProceeds(user1);
        uint256 actualUser2 = pool.getPendingProceeds(user2);
        
        // Calculate reasonable tolerance based on scale
        uint256 tolerance = (proceeds / 10000) + 1000;
        
        assertApproxEqAbs(actualUser1, expectedUser1, tolerance);
        assertApproxEqAbs(actualUser2, expectedUser2, tolerance);
        
        // Verify total distribution
        uint256 totalDistributed = actualUser1 + actualUser2;
        assertApproxEqAbs(totalDistributed, proceeds, tolerance);
    }
    
    /**
     * @notice Test complete user journey
     */
    function test_CompleteUserJourney() public {
        // 1. User deposits USD tokens
        vm.startPrank(user1);
        pool.deposit(DEPOSIT_AMOUNT);
        assertEq(pool.balanceOf(user1), DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 2. Admin adds proceeds
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // 3. User transfers some tokens
        vm.startPrank(user1);
        pool.transfer(user2, DEPOSIT_AMOUNT / 2);
        assertEq(pool.getPendingProceeds(user1), PROCEEDS_AMOUNT); // Keeps full proceeds
        assertEq(pool.getPendingProceeds(user2), 0); // Starts fresh
        vm.stopPrank();
        
        // 4. More proceeds added (tests future distribution)
        vm.startPrank(admin);
        pool.depositProceeds(PROCEEDS_AMOUNT);
        vm.stopPrank();
        
        // 5. User claims proceeds
        vm.startPrank(user1);
        uint256 balanceBefore = usdToken.balanceOf(user1);
        pool.claimProceeds();
        assertGt(usdToken.balanceOf(user1), balanceBefore);
        assertEq(pool.getPendingProceeds(user1), 0);
        vm.stopPrank();
        
        // 6. User withdraws (tests force claim requirement)
        vm.startPrank(user2);
        pool.withdraw(pool.balanceOf(user2));
        assertEq(pool.getPendingProceeds(user2), 0); // No outstanding proceeds
        vm.stopPrank();
    }
}