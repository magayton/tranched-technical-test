// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Pool - Redeemable Vault Contract
 * @notice A vault that accepts USD token deposits and distributes proceeds proportionally
 * This contract acts as :
 * - An ERC20 token representing user shares in the pool
 * - The vault business logic for deposits, withdrawals, and proceeds distribution
 */
contract Pool is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    
    /// @notice The underlying USD token that users deposit
    IERC20 public usdToken;
    
    /// @notice Cumulative rewards per share, scaled by PRECISION for mathematical accuracy
    // Updated when proceeds deposited: cumulativeRewardsPerShare += (proceeds * PRECISION) / totalSupply()
    // This tracks the total rewards per share that have ever been distributed
    uint256 public cumulativeRewardsPerShare;
    
    /// @notice Each user's checkpoint for reward calculations
    // When user claims: set to current cumulativeRewardsPerShare
    // Used to calculate: (current - checkpoint) * balance = new proceeds since last interaction
    mapping(address => uint256) public lastRewardPerShare;
    
    /// @notice Locked proceeds that preserve historical earnings during token transfers
    // When user transfers tokens, their current proceeds get "locked" at that amount
    // These proceeds remain claimable regardless of future token balance changes
    mapping(address => uint256) public lockedProceeds;
    
    /// @notice Proceeds waiting to be distributed when totalSupply is zero
    // Edge case: if proceeds deposited when no pool tokens exist, store for first depositor
    // First depositor gets these as bonus since they can't be distributed proportionally
    uint256 public pendingProceedsForZeroSupply;
    
    /// @notice Total proceeds ever deposited into the pool (for analytics)
    uint256 public totalProceedsDeposited;
    
    /// @notice Precision multiplier for reward calculations (prevents precision loss)
    uint256 private constant PRECISION = 1e18;
    
    /// @notice Emitted when user deposits USD tokens and receives pool tokens
    event Deposit(address indexed user, uint256 usdAmount, uint256 poolTokensMinted);
    
    /// @notice Emitted when user withdraws pool tokens for USD tokens
    event Withdrawal(address indexed user, uint256 poolTokensBurned, uint256 usdReceived);
    
    /// @notice Emitted when admin deposits proceeds for distribution
    event ProceedsDeposited(address indexed admin, uint256 amount, uint256 newCumulativeRewardsPerShare);
    
    /// @notice Emitted when user claims their accumulated proceeds
    event ProceedsClaimed(address indexed user, uint256 amount);
    
    /// @notice Emitted when zero-supply proceeds are given to first depositor
    event ZeroSupplyProceedsDistributed(address indexed firstDepositor, uint256 amount);
    
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error TransferFailed();
    
    
    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }
    
    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }
    
    /**
     * @notice Initialize the pool contract (replaces constructor for upgradeable contracts)
     * @param _usdToken Address of the USD token contract
     * @param _admin Address that will own the contract and can deposit proceeds
     * @param _name Name for the pool token (e.g., "Pool USD Token")
     * @param _symbol Symbol for the pool token (e.g., "pUSD")
     * 
     * Must be called immediately after proxy deployment
     * Can only be called once due to initializer modifier
     */
    function initialize(
        address _usdToken,
        address _admin,
        string memory _name,
        string memory _symbol
    ) external initializer nonZeroAddress(_usdToken) nonZeroAddress(_admin) {
        // Initialize parent contracts
        __ERC20_init(_name, _symbol);
        __Ownable_init(_admin);
        __ReentrancyGuard_init();
        
        // Set USD token reference for vault operations
        usdToken = IERC20(_usdToken);
        
        // Initialize state variables for clarity
        cumulativeRewardsPerShare = 0;
        pendingProceedsForZeroSupply = 0;
        totalProceedsDeposited = 0;
    }
    
    /**
     * @notice Deposit USD tokens and receive pool tokens at 1:1 ratio
     * @param amount Amount of USD tokens to deposit
     * 
     * Process:
     * 1. Transfer USD tokens from user to this contract
     * 2. Mint equivalent pool tokens to user (1:1 conversion)
     * 3. Set user's reward checkpoint to current level (no retroactive proceeds)
     * 4. Handle zero-supply proceeds bonus if applicable
     * 
     * Zero-supply edge case:
     * - If this is first deposit and proceeds were stored, give them as bonus
     * - First depositor enables the pool
     */
    function deposit(uint256 amount) external nonZeroAmount(amount) nonReentrant {
        address user = msg.sender;
        
        // Check for zero-supply proceeds bonus (first depositor gets stored proceeds)
        bool isFirstDepositAfterZeroSupply = totalSupply() == 0 && pendingProceedsForZeroSupply > 0;
        uint256 bonusProceeds = isFirstDepositAfterZeroSupply ? pendingProceedsForZeroSupply : 0;
        
        // Transfer USD tokens from user to this contract
        bool success = usdToken.transferFrom(user, address(this), amount);
        if (!success) revert TransferFailed();
        
        // Mint pool tokens 1:1 with deposited USD
        _mint(user, amount);
        
        // Set user's reward checkpoint to current level (no retroactive proceeds)
        // This prevents claiming proceeds from before they joined the pool
        lastRewardPerShare[user] = cumulativeRewardsPerShare;
        
        // Handle zero-supply bonus proceeds if applicable
        if (isFirstDepositAfterZeroSupply) {
            bool proceedsSuccess = usdToken.transfer(user, bonusProceeds);
            if (!proceedsSuccess) revert TransferFailed();
            
            // Clear stored proceeds after distribution
            pendingProceedsForZeroSupply = 0;
            
            emit ZeroSupplyProceedsDistributed(user, bonusProceeds);
        }
        
        emit Deposit(user, amount, amount);
    }
    
    /**
     * @notice Withdraw pool tokens for USD tokens with automatic proceeds claiming
     * @param amount Amount of pool tokens to burn and convert to USD
     * 
     * Force claim all proceeds on any withdrawal
     * This is the chosen strategy to satisfy the "no outstanding proceeds" requirement
     */
    function withdraw(uint256 amount) external nonZeroAmount(amount) nonReentrant {
        address user = msg.sender;
        
        // Verify user has sufficient pool tokens
        if (balanceOf(user) < amount) revert InsufficientBalance();
        
        // STEP 1: Force claim all pending proceeds
        _claimAllProceeds(user);
        
        // STEP 2: Burn pool tokens
        _burn(user, amount);
        
        // STEP 3: Transfer equivalent USD tokens to user (1:1 conversion)
        bool success = usdToken.transfer(user, amount);
        if (!success) revert TransferFailed();
        
        emit Withdrawal(user, amount, amount);
    }
    
    /**
     * @notice Deposit proceeds to be distributed proportionally to pool token holders
     * @param amount Amount of USD tokens to deposit as proceeds
     * 
     * Distribution math explanation:
     * - cumulativeRewardsPerShare += (amount * PRECISION) / totalSupply()
     * - Each existing holder gets: (new rewards per share) * (their balance)
     * - New holders start from the updated cumulative level (no retroactive proceeds)
     */
    function depositProceeds(uint256 amount) external onlyOwner nonZeroAmount(amount) nonReentrant {
        uint256 currentTotalSupply = totalSupply();
        
        if (currentTotalSupply == 0) {
            // Edge case no pool tokens exist, can't divide by zero
            // Store proceeds for distribution to first depositor
            pendingProceedsForZeroSupply += amount;
        } else {
            // Normal case distribute proceeds proportionally to current holders
            // Add to cumulative rewards per share 
            uint256 rewardsPerShare = (amount * PRECISION) / currentTotalSupply;
            cumulativeRewardsPerShare += rewardsPerShare;
        }
        
        // Transfer proceeds from admin to this contract
        bool success = usdToken.transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();
        
        totalProceedsDeposited += amount;
        
        emit ProceedsDeposited(msg.sender, amount, cumulativeRewardsPerShare);
    }
    
    /**
     * @notice Manually claim accumulated proceeds without withdrawing pool tokens
     * This is the "withdrawal mechanism" for proceeds
     * 
     * Users can call this anytime to claim without affecting their pool token balance
     */
    function claimProceeds() external nonReentrant {
        _claimAllProceeds(msg.sender);
    }
    
    /**
     * @notice Calculate total pending proceeds for a user
     * @param user Address to check proceeds for
     * @return total amount of USD tokens user can claim as proceeds
     * 
     * Components explanation:
     * - lockedProceeds[user]: Historical proceeds "locked" from previous pool token transfers
     * - (cumulativeRewardsPerShare - lastRewardPerShare[user]): New rewards per share since last interaction
     * - Multiply by current balance: User's share of new proceeds based on current holdings
     * - PRECISION scaling: Maintains mathematical accuracy with large numbers
     */
    function getPendingProceeds(address user) public view returns (uint256 total) {
        uint256 userBalance = balanceOf(user);
        uint256 userLastReward = lastRewardPerShare[user];
        uint256 rewardsSinceLastClaim = cumulativeRewardsPerShare - userLastReward;
        
        // Calculate new proceeds based on current balance and checkpoint
        uint256 newProceeds = (rewardsSinceLastClaim * userBalance) / PRECISION;
        
        return lockedProceeds[user] + newProceeds;
    }
    
    /**
     * @notice Get total USD tokens held by this contract
     */
    function getTotalUSDBalance() external view returns (uint256) {
        return usdToken.balanceOf(address(this));
    }
    
    /**
     * @notice Get contract state information
     * @return totalSupply_ Total pool tokens in circulation
     * @return totalUSDHeld Total USD tokens held by contract
     * @return totalProceeds Total proceeds ever deposited
     * @return pendingForZeroSupply Proceeds stored for first depositor
     * @return cumulativeRewards Current cumulative rewards per share
     */
    function getContractInfo() external view returns (
        uint256 totalSupply_,
        uint256 totalUSDHeld,
        uint256 totalProceeds,
        uint256 pendingForZeroSupply,
        uint256 cumulativeRewards
    ) {
        return (
            totalSupply(),
            usdToken.balanceOf(address(this)),
            totalProceedsDeposited,
            pendingProceedsForZeroSupply,
            cumulativeRewardsPerShare
        );
    }
    
    /**
     * @notice Get user information
     * @param user Address to check
     * @return poolBalance User's pool token balance
     * @return pendingProceeds User's total claimable proceeds (locked + new)
     * @return lastRewardCheckpoint User's last reward checkpoint
     * @return lockedProceedsAmount User's locked proceeds from transfers
     */
    function getUserInfo(address user) external view returns (
        uint256 poolBalance,
        uint256 pendingProceeds,
        uint256 lastRewardCheckpoint,
        uint256 lockedProceedsAmount
    ) {
        return (
            balanceOf(user),
            getPendingProceeds(user),
            lastRewardPerShare[user],
            lockedProceeds[user]
        );
    }
    
    
    /**
     * @notice Internal function to claim all pending proceeds for a user
     * @param user Address to claim proceeds for
     * 
     * This function is called by both claimProceeds() and withdraw()
     */
    function _claimAllProceeds(address user) internal {
        uint256 pending = getPendingProceeds(user);
        
        if (pending == 0) {
            return;
        }
        
        // Update user's checkpoint to current cumulative rewards
        // This prevents double-claiming of the same proceeds
        lastRewardPerShare[user] = cumulativeRewardsPerShare;
        
        // Clear locked proceeds since we're claiming everything
        lockedProceeds[user] = 0;
        
        bool success = usdToken.transfer(user, pending);
        if (!success) revert TransferFailed();
        
        emit ProceedsClaimed(user, pending);
    }
    
    /**
    * @notice Override token update to handle proceeds during transfers and mints
    * 
    * Transfer behavior:
    * - When tokens are transferred, sender's current proceeds get "locked" and added to existing locked proceeds
    * - Receiver's existing proceeds are auto-claimed before they receive tokens
    * - Both sender and receiver start earning new proceeds based on their new balances going forward
    * 
    * Mint behavior :
    * - On first deposit: User starts fresh with current reward level (no retroactive proceeds)
    * - On subsequent deposits: User's existing proceeds are auto-claimed before new tokens are minted
    * - New tokens start fresh - no retroactive proceeds from previous distributions
    */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Handle token transfers
        if (from != address(0) && to != address(0)) {
            // Sender logic
            // Calculate only new proceeds since last checkpoint before balance changes
            uint256 rewardsSinceLastClaim = cumulativeRewardsPerShare - lastRewardPerShare[from];
            uint256 newProceeds = (rewardsSinceLastClaim * balanceOf(from)) / PRECISION;
            
            // Lock only the NEW proceeds (avoid double-counting already locked proceeds)
            lockedProceeds[from] += newProceeds;
            
            // Reset sender's checkpoint so they start earning new proceeds fresh with new balance
            lastRewardPerShare[from] = cumulativeRewardsPerShare;
            
            // Receiver logic before balance update
            // Claim receiver's existing proceeds before their balance changes
            // This ensures proceeds are calculated with their old balance
            _claimAllProceeds(to);
            
            // Update balances
            super._update(from, to, value);
            
            // Receiver starts fresh with current reward level for future earnings
            lastRewardPerShare[to] = cumulativeRewardsPerShare;
            return;
        }
        
        // minting logic for deposits
        if (from == address(0) && to != address(0)) {
            // Check if user already has tokens (subsequent deposit)
            if (balanceOf(to) > 0) {
                // Claim existing proceeds before minting new tokens
                // This preserves their earned proceeds based on old balance
                _claimAllProceeds(to);
            }
        }
        
        // Update balances after handling proceeds
        super._update(from, to, value);
        
        // Post mint logic
        if (from == address(0) && to != address(0)) {
            // New tokens start fresh
            // This prevents new tokens from claiming proceeds they didn't earn
            lastRewardPerShare[to] = cumulativeRewardsPerShare;
        }
        
        // Handle burning (withdrawals) : no special handling needed
        // withdraw() function already handles proceeds claiming before burning
    }
    
    /**
     * @notice Storage gap for future upgrades
     * Reserves 50 storage slots for future variables in contract upgrades
     * This prevents storage collisions when adding new features in upgraded versions
     */
    uint256[50] private __gap;
}