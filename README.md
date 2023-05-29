# StakingEligibility

StakingEligibility is an eligibility module for [Hats Protocol](https://github.com/hats-protocol/hats-protocol). It requires wearers of a given Hat to stake a minimum amount of a specified token in order to be eligible, and enables others in the hat tree's organization to slash the stake of a wearer who is behaving badly.

## StakingEligibility Details

StakingEligibility inherits from the [HatsEligibilityModule](https://github.com/Hats-Protocol/hats-module#hatseligibilitymodule) base contract, from which it receives two major properties:

- It can be cheaply deployed via the [HatsModuleFactory](https://github.com/Hats-Protocol/hats-module#hatsmodulefactory) minimal proxy factory, and
- It implements the [IHatsEligibility](https://github.com/Hats-Protocol/hats-protocol/blob/main/src/Interfaces/IHatsEligibility.sol) interface

### Setup

A StakingEligibility instance requires several parameters to be set at deployment, passed to the `HatsModuleFactory.createHatsModule()` function in various ways.

#### Immutable values

- `hatId`: The id of the hat to which this the instance will be attached as an eligibility module, passed as itself
- `TOKEN`: The address of the ERC20-compatible staking token, abi-encoded (packed) and passed as `_otherImmutableArgs`

The following immutable values will also automatically be set within the instance at deployment:

- `IMPLEMENTATION`: The address of the StakingEligibility implementation contract
- `HATS`: The address of the Hats Protocol contract

#### Initial state values

The following are abi-encoded (unpacked) and then passed to the `HatsModuleFactory.createHatsModule()` function as `_initData`. These values can be changed after deployment by an admin of the `hatId` hat.

- `minStake`: The minimum amount of the staking token that must be staked in order to be eligible for the hat
- `judgeHat`: The id of the hat that has the authority to slash stakes
- `recipientHat`: The id of the hat that receives
- `cooldownPeriod`: The amount of time that must pass between beginning an unstaking process and completing it. This is to give the wearer of the `judgeHat` time to slash the stake of a misbehaving wearer before they can remove their stake, so it should be long enough to allow for that based on the governance process of the wearer of the `judgeHat`.

### Staking

In order to be eligible for a hat, a user must stake at least the `minStake` amount of the staking token. This is done by calling the `stake()` function, which transfers the staking token from the caller to the StakingEligibility instance. The caller must have approved the StakingEligibility instance to transfer at least the `minStake` amount of the staking token.

### Unstaking

Unstaking involves two steps: (1) beginning an unstaking cooldown period, and then (2) completing the unstaking process once the cooldown period has ended. This cooldown period exists to give a wearer of the `judgeHat` (see [Slashing](#slashing)) enough time to slash the stake of a misbehaving wearer before they can remove their stake.

1. `beginUnstake()`: This initiates the unstaking process and begins a cooldown period. It does not transfer any tokens, but it removes the specified amount from the caller's stake. If this drops the caller's stake below the `minStake`, they will immediately lose their eligibility. A staker cannot have two concurrent unstaking cooldown periods, so this function reverts if the caller already is in a cooldown period.

2. `completeUnstake()`: Once the cooldown period ends, this function can be called to finish the unstaking process. It transfers the amount of tokens specified in (1) from the StakingEligibility instance to the specified staker, and then clears the cooldown data. This function reverts if the caller is not in a cooldown period.

### Slashing

A staker's stake can be slashed by calling the `slash()` function. This updates internal balances within StakingEligibility, removing the staker's entire stake and any pending unstaking amount. The slashed staker will lose their eligibility, and will also be placed in bad standing; they will not be able to stake again unless a judge calls the `forgive()` function.

Only a wearer of the `judgeHat` can slash.

### Forgiving

A slashed staker can be forgiven by calling the `forgive()` function. This does not unslash the staker, but it brings them out of bad standing and allows them to stake again if they wish.

Only a wearer of the `judgeHat` can forgive.

### Withdrawal

Slashed stakes can be withdrawn by calling the `withdraw()` function. This transfers the full `totalSlashedStakes` balance to the (specified) wearer of the `recipientHat`, and removes the slashed stake from the internal balances of StakingEligibility.

Anybody can execute a withdrawal, but the tokens will always be transferred to the specified wearer of the `recipientHat`.

### Changing Parameters

The following parameters can be changed after deployment by an admin of the `hatId` hat. Changes are only allowed while the `hatId` is mutable.

- `minStake`, by calling the `changeMinStake()` function
- `cooldownPeriod`, by calling the `changeCooldownPeriod()` function
- `judgeHat`, by calling the `changeJudgeHat()` function
- `recipientHat`, by calling the `changeRecipientHat()` function

## Development

This repo uses Foundry for development and testing. To get started:

1. Fork the project
2. Install [Foundry](https://book.getfoundry.sh/getting-started/installation)
3. To compile the contracts, run `forge build`
4. To test, run `forge test`
