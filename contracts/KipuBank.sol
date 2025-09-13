// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title KipuBank
 * @author Renato Ribeiro
 * @notice A minimal ETH vault with per-tx withdrawal limit and a global bank cap.
 * @dev Demonstrates secure Solidity practices for ETH handling, custom errors,
 *      NatSpec, events, immutables, modifiers, and CEI (checks-effects-interactions).
 */
contract KipuBank {
    // ============
    //  Constants
    // ============

    /// @notice Human-readable contract version.
    string public constant VERSION = "1.0.0";

    // ============
    //  Immutables
    // ============

    /// @notice Max total ETH (in wei) the bank will accept across all users.
    /// @dev Set once in the constructor and never changes.
    uint256 public immutable bankCap;

    /// @notice Per-transaction withdrawal ceiling (in wei).
    /// @dev Set once in the constructor and never changes.
    uint256 public immutable withdrawLimit;

    // ============
    //  Storage
    // ============

    /// @notice Total ETH (in wei) held by the bank (sum of all user balances).
    uint256 public totalVaultBalance;

    /// @notice Per-user ETH balances (in wei).
    mapping(address => uint256) private _balanceOf;

    /// @notice Global counters for deposits/withdrawals.
    uint256 public depositCount;
    uint256 public withdrawalCount;

    /// @notice Per-user counters (optional but nice for UX/analytics).
    mapping(address => uint256) public userDepositCount;
    mapping(address => uint256) public userWithdrawalCount;

    /// @dev Simple non-reentrancy guard (no OZ imports to keep this self-contained).
    bool private _locked;

    // ============
    //  Events
    // ============

    /**
     * @notice Emitted on successful deposit.
     * @param account The depositor.
     * @param amount  Amount of ETH received (wei).
     * @param newUserBalance User balance after deposit (wei).
     * @param newTotalVaultBalance Total bank balance after deposit (wei).
     */
    event Deposited(address indexed account, uint256 amount, uint256 newUserBalance, uint256 newTotalVaultBalance);

    /**
     * @notice Emitted on successful withdrawal.
     * @param account The withdrawer.
     * @param amount  Amount of ETH sent out (wei).
     * @param newUserBalance User balance after withdrawal (wei).
     * @param newTotalVaultBalance Total bank balance after withdrawal (wei).
     */
    event Withdrawn(address indexed account, uint256 amount, uint256 newUserBalance, uint256 newTotalVaultBalance);

    // ============
    //  Custom Errors
    // ============

    /// @notice Thrown when caller tries to deposit zero or withdraw zero.
    error AmountZero();

    /// @notice Thrown when a deposit would exceed the global bank cap.
    /// @param attempted Total vault balance that would result if allowed.
    /// @param cap The configured bank cap.
    error BankCapExceeded(uint256 attempted, uint256 cap);

    /// @notice Thrown when withdrawal exceeds the configured per-tx limit.
    /// @param amount Requested amount.
    /// @param limit The per-tx limit.
    error WithdrawLimitExceeded(uint256 amount, uint256 limit);

    /// @notice Thrown when user tries to withdraw more than their balance.
    /// @param amount Requested amount.
    /// @param balance Current user balance.
    error InsufficientBalance(uint256 amount, uint256 balance);

    /// @notice Thrown when someone sends ETH directly to the contract without using deposit().
    error DirectTransferDisabled();

    /// @notice Thrown when a low-level ETH transfer fails.
    error EtherTransferFailed();

    // ============
    //  Modifiers
    // ============

    /**
     * @notice Prevents re-entrancy on state-changing external functions.
     */
    modifier nonReentrant() {
        if (_locked) revert();
        _locked = true;
        _;
        _locked = false;
    }

    // ============
    //  Constructor
    // ============

    /**
     * @notice Initializes the bank with a global cap and per-transaction withdrawal limit.
     * @param _bankCap Max total ETH (wei) this bank can hold at any time.
     * @param _withdrawLimit Max ETH (wei) a user can withdraw per transaction.
     */
    constructor(uint256 _bankCap, uint256 _withdrawLimit) {
        require(_bankCap > 0 && _withdrawLimit > 0, "Invalid init");
        bankCap = _bankCap;
        withdrawLimit = _withdrawLimit;
    }

    // ============
    //  External
    // ============

    /**
     * @notice Deposit ETH to your personal vault.
     * @dev Follows CEI. Updates state then emits event. Direct transfers are disabled; use this function.
     * @custom:error AmountZero When msg.value == 0
     * @custom:error BankCapExceeded When totalVaultBalance + msg.value > bankCap
     */
    function deposit() external payable {
        if (msg.value == 0) revert AmountZero();

        uint256 newTotal = totalVaultBalance + msg.value;
        if (newTotal > bankCap) revert BankCapExceeded(newTotal, bankCap);

        // Effects
        _balanceOf[msg.sender] += msg.value;
        totalVaultBalance = newTotal;

        unchecked {
            // Overflow not possible in realistic scenarios
            depositCount += 1;
            userDepositCount[msg.sender] += 1;
        }

        // Interactions: none (ETH already received)

        emit Deposited(msg.sender, msg.value, _balanceOf[msg.sender], totalVaultBalance);
    }

    /**
     * @notice Withdraw ETH from your vault (capped by `withdrawLimit` per tx).
     * @param amount Amount (wei) to withdraw.
     * @dev Uses nonReentrant guard + CEI + safe call.
     * @custom:error AmountZero When amount == 0
     * @custom:error WithdrawLimitExceeded When amount > withdrawLimit
     * @custom:error InsufficientBalance When amount > user balance
     * @custom:error EtherTransferFailed When low-level call fails
     */
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert AmountZero();
        if (amount > withdrawLimit) revert WithdrawLimitExceeded(amount, withdrawLimit);

        uint256 bal = _balanceOf[msg.sender];
        if (amount > bal) revert InsufficientBalance(amount, bal);

        // Effects
        unchecked {
            _balanceOf[msg.sender] = bal - amount;
        }
        totalVaultBalance -= amount;

        unchecked {
            withdrawalCount += 1;
            userWithdrawalCount[msg.sender] += 1;
        }

        // Interactions
        _payout(msg.sender, amount);

        emit Withdrawn(msg.sender, amount, _balanceOf[msg.sender], totalVaultBalance);
    }

    /**
     * @notice Read-only view into a user's vault balance.
     * @param account Address to query.
     * @return balance The current balance (wei) for `account`.
     */
    function balanceOf(address account) external view returns (uint256 balance) {
        return _balanceOf[account];
    }

    // ============
    //  Private
    // ============

    /**
     * @dev Internalized ETH transfer using call pattern. Reverts on failure.
     * @param to Recipient address.
     * @param amount Amount (wei).
     */
    function _payout(address to, uint256 amount) private {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert EtherTransferFailed();
    }

    // ============
    //  Fallbacks
    // ============

    /// @dev Disable direct ETH transfers. Enforces use of deposit().
    receive() external payable {
        revert DirectTransferDisabled();
    }

    /// @dev Disable unknown function calls.
    fallback() external payable {
        revert DirectTransferDisabled();
    }
}
