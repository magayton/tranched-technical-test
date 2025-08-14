# Smart-contract engineer assignment

## Introduction

Welcome!

These exercises are part of the application process for the Smart Contract Engineer role.  
Our goal is to provide challenges similar to those you might encounter while developing the Tranched protocol.  

By assessing your solutions, we aim to gain a better understanding of how you approach problem-solving and determine if you'd be a good fit for the role.

## Exercise 1 - Redeemable Vault

The idea is to create an application that allows users to deposit tokens and later receive dividend payouts (proceeds) proportional to their tokens deposited initially. The business logic that governs how these proceeds are generated is out of scope for this exercise, the focus is mainly on token deposits and proceeds dispersion.

As a base structure, we expect 2 token contracts:
- The first one represents an underlying asset (USD token).
- The second represents the pool into which the first token can be deposited.

### Functionality expected of the USD token

#### 1. Minting

 - Any user should be able to mint any amount of USD tokens.

### Functionality expected of the pool

The pool should be a token contract, which USD tokens can be deposited and withdrawn in exchange for pool tokens.

#### 1. Deposits

 - Depositing USD tokens should grant the user with pool tokens (through a **1:1** conversion).
 - The contract should hold onto the USD tokens for now.
 - This method should be executable by any user.

#### 2. Deposit proceeds

 - Proceeds are essentially USD tokens that should be dispersed to the pool token holders.
 - Proceeds should be newly minted tokens from the USD token smart-contract.

#### 3. Proceeds withdrawal/distribution

 - A mechanism for users to withdraw proceeds, or for the contract to distribute proceeds to the user.
 - The proceeds should be distributed based on each user's relative share of the total supply of pool tokens at that time.

#### 4. Withdrawals

 - The user should be able to convert their tokens back to USD tokens.
 - The user shouldn't have any outstanding proceed withdrawals after withdrawing, if withdrawals were the chosen method.

### Bonuses

1. Demonstrate knowledge of proxied contract upgradability using diamonds or other methods.
2. Add tests to the protocol and demonstrate that it is not prone to attacks or bad debt.


## Exercise 2 - Vault Attack 

The objective is to find a way to empty a [deployed vault on the Sepolia Optimism network](https://sepolia-optimism.etherscan.io/address/0x92d2730Bb4cC6D6F836B6d47c5ea4a791e391821).

To assist you, the code of the contract is as follows:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract BananaVault {
    uint256 private salt_GNGYHBFD;
    uint256 private hiddenPassword = 123_456_789;

    error IncorrectPassword();

    constructor(uint256 initialSeed) {
        salt_GNGYHBFD = block.timestamp;
        hiddenPassword |= initialSeed;
    }

    function updateHiddenPassword_YGSBFYE(uint256 newSeed) external {
        hiddenPassword |= newSeed;
    }

    function claimBanana_NNVGDUJE(uint256 password) external {
        if (
            password
                != uint256(keccak256(abi.encode(hiddenPassword + salt_GNGYHBFD)))
        ) {
            revert IncorrectPassword();
        }
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) {
            revert();
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
```

This exercise will be considered complete if the contract at address `0x92d2730Bb4cC6D6F836B6d47c5ea4a791e391821` is entirely emptied, and your script is committed here.


## Exercise 3 - Blind Vault Attack 

The objective of this exercise is to find a way to empty a [deployed vault on the Sepolia Optimism network](https://sepolia-optimism.etherscan.io/address/0x931188d102a8cFe2FAC8B698D350B9BB902e2EB0) but this time without the code of the contract or any ABI.

This exercise will be considered complete if the contract at address `0x931188d102a8cFe2FAC8B698D350B9BB902e2EB0` is entirely emptied, and your script is committed here.  

To assist you, the contract was deployed via [this transaction](https://sepolia-optimism.etherscan.io/tx/0x75f649c67e1c48bb32d5ec2e6fc74d77cf9362024b1c4a1e3a60bef0cc23e961).  
You may use any tools at your disposal to find a way to break-in incognito.


## Additional instructions

- Please send us an archive containing your solutions via email once your work is complete.
- Do not hesitate to ask questions by emailing us directly.
- You may not complete all exercises, but we will assess the quality and outcome of your solutions.