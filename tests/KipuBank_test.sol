// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Remix provides these imports for Solidity unit tests
import "remix_tests.sol";      // gives you `Assert` and test framework
import "remix_accounts.sol";   // gives you sample accounts for testing

import "../contracts/KipuBank.sol";

contract KipuBankTest {
    KipuBank bank;
    address acc0; // test accounts
    address acc1;

    // Called before each test
    function beforeEach() public {
        bank = new KipuBank(3 ether, 1 ether); // bankCap=3 ETH, withdrawLimit=1 ETH

        // get test accounts from remix_accounts.sol
        acc0 = TestsAccounts.getAccount(0);
        acc1 = TestsAccounts.getAccount(1);
    }

    function testInitialState() public {
        Assert.equal(bank.totalVaultBalance(), uint256(0), "Vault should start empty");
        Assert.equal(bank.depositCount(), uint256(0), "No deposits yet");
    }

    /// #value: 1000000000000000000   (1 ether sent with this call)
    function testDepositUpdatesBalance() public payable {
        // this contract deposits 1 ETH into KipuBank
        bank.deposit{value: msg.value}();
        uint256 bal = bank.balanceOf(address(this));
        Assert.equal(bal, msg.value, "Balance should update after deposit");
        Assert.equal(bank.totalVaultBalance(), msg.value, "Total vault should equal deposit");
    }

    function testWithdrawRevertsIfZero() public {
        try bank.withdraw(0) {
            Assert.ok(false, "Withdraw 0 should revert");
        } catch {
            Assert.ok(true, "Expected revert on zero withdraw");
        }
    }
}
