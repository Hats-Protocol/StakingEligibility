// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import {
  StakingEligibility,
  IERC20,
  HatsModuleFactory,
  StakingEligibilityTest,
  WithInstanceTest,
  DeployImplementation
} from "test/StakingEligibility.t.sol";
import { Hats } from "hats-protocol/Hats.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { StakingHandler, BoundedStakingHandler, IStakingHandler } from "test/handlers/StakingHandler.sol";
import { SlashingHandler, BoundedSlashingHandler, ISlashingHandler } from "test/handlers/SlashingHandler.sol";
import { AdminHandler, BoundedAdminHandler, IAdminHandler } from "test/handlers/AdminHandler.sol";

contract StakingEligibilityInvariantBase is StakingEligibilityTest {
  IStakingHandler public stakingHandler;
  ISlashingHandler public slashingHandler;
  IAdminHandler public adminHandler;

  bytes4[] stakingSelectors;
  bytes4[] slashingSelectors;
  bytes4[] adminSelectors;

  uint256 sumOfStakes;
  uint256 sumOfStakerSlashes;
  uint256 sumOfStakerBalances;
  uint256 sumOfStakerCooldowns;
  uint256 sumOfRecipientBalances;
  uint256 cumulativeStakerStakes;

  uint256 tokenSupply;
  uint256 cumulativeTotalUnstakesCompleted;
  uint256 cumulativeTotalSlashes;
  uint256 currentTotalValidStakes;
  uint256 currentTotalUnstakesBegun;
  uint256 cumulativeTotalWithdrawals;

  uint256 stakerStakes;
  uint256 stakerCooldowns;
  // uint256 stakerBalance; // inherited
  uint256 cumulativeStakerSlashes;
  address[] stakers;
  address[] recipients;

  // per staker values
  uint256 stakeAmount;
  uint256 cooldownAmount;
  uint256 slashAmount;

  function deployDependencies() public {
    // deploy a test version of Hats Protocol since we're not using the fork tests here
    /// @dev Hats.sol needs the solc optimizer *on* in order to compile without stack too deep errors
    hats = new Hats{ salt: SALT}( "test Hats Protocol", "https://hatsprotocol.xyz");
    // deploy the module contracts
    deployFactoryContracts();
    // set up the dao's hats
    createHats();

    // set deploy params
    token = IERC20(new ERC20("DST", "DAO Staking Token")); // test ERC20
    minStake = 1000;
    cooldownPeriod = 1 hours;

    // deploy the instance
    deployInstance(stakerHat, address(token), minStake, judgeHat, recipientHat, cooldownPeriod);

    // change the stakerHat's eligibility to instance
    vm.prank(dao);
    hats.changeHatEligibility(stakerHat, address(instance));
  }

  function configureScope() public {
    stakingSelectors = new bytes4[](3);
    stakingSelectors[0] = IStakingHandler.stake.selector;
    stakingSelectors[1] = IStakingHandler.beginUnstake.selector;
    stakingSelectors[2] = IStakingHandler.completeUnstake.selector;

    targetSelector(FuzzSelector({ addr: address(stakingHandler), selectors: stakingSelectors }));
    targetContract(address(stakingHandler));

    slashingSelectors = new bytes4[](2);
    slashingSelectors[0] = ISlashingHandler.slash.selector;
    slashingSelectors[1] = ISlashingHandler.withdraw.selector;

    targetSelector(FuzzSelector({ addr: address(slashingHandler), selectors: slashingSelectors }));
    targetContract(address(slashingHandler));

    adminSelectors = new bytes4[](4);
    adminSelectors[0] = IAdminHandler.changeMinStake.selector;
    adminSelectors[1] = IAdminHandler.changeCooldownPeriod.selector;
    adminSelectors[2] = IAdminHandler.changeJudgeHat.selector;
    adminSelectors[3] = IAdminHandler.changeRecipientHat.selector;

    targetSelector(FuzzSelector({ addr: address(adminHandler), selectors: adminSelectors }));
    targetContract(address(adminHandler));

    // exclude instance and handlers from fuzz scope
    excludeSender(address(instance));
    excludeSender(address(stakingHandler));
    excludeSender(address(slashingHandler));
    excludeSender(address(adminHandler));
  }

  function callSummary() public {
    uint256 stakeCalls = stakingHandler.numCalls(stakingSelectors[0]);
    uint256 beginUnstakeCalls = stakingHandler.numCalls(stakingSelectors[1]);
    uint256 completeUnstakeCalls = stakingHandler.numCalls(stakingSelectors[2]);

    uint256 slashCalls = slashingHandler.numCalls(slashingSelectors[0]);
    uint256 withdrawCalls = slashingHandler.numCalls(slashingSelectors[1]);

    uint256 changeMinStakeCalls = adminHandler.numCalls(adminSelectors[0]);
    uint256 changeCooldownPeriodCalls = adminHandler.numCalls(adminSelectors[1]);
    uint256 changeJudgeHatCalls = adminHandler.numCalls(adminSelectors[2]);
    uint256 changeRecipientHatCalls = adminHandler.numCalls(adminSelectors[3]);

    uint256 sumOfStakingCalls = stakeCalls + beginUnstakeCalls + completeUnstakeCalls;
    uint256 sumOfSlashingCalls = slashCalls + withdrawCalls;
    uint256 sumOfAdminCalls =
      changeMinStakeCalls + changeCooldownPeriodCalls + changeJudgeHatCalls + changeRecipientHatCalls;

    uint256 sumOfCalls = sumOfStakingCalls + sumOfSlashingCalls + sumOfAdminCalls;

    console2.log("\nLatest Run Call Summary\n");
    console2.log("stake           ", stakeCalls);
    console2.log("beginUnstake    ", beginUnstakeCalls);
    console2.log("completeUnstake ", completeUnstakeCalls);
    console2.log("...................");
    console2.log("staking calls   ", sumOfStakingCalls, "\n");

    console2.log("slash           ", slashCalls);
    console2.log("withdraw        ", withdrawCalls);
    console2.log("...................");
    console2.log("slashing calls  ", sumOfSlashingCalls, "\n");

    console2.log("changeMinStake  ", changeMinStakeCalls);
    console2.log("changeCooldown  ", changeCooldownPeriodCalls);
    console2.log("changeJudgeHat  ", changeJudgeHatCalls);
    console2.log("changeRecipHat  ", changeRecipientHatCalls);
    console2.log("...................");
    console2.log("admin calls     ", sumOfAdminCalls, "\n");

    console2.log("-------------------");
    console2.log("Sum of calls    ", sumOfCalls);
  }

  /*//////////////////////////////////////////////////////////////
                            ASSERTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * A. Individual Staker Solvency
   */
  function assert_invariant_A() public {
    assertEq(
      cumulativeStakerStakes, stakerStakes + stakerCooldowns + stakerBalance + cumulativeStakerSlashes, "invariant A"
    );
  }

  /**
   * B. Completed Unstakes Solvency
   *  cumulative total completed unstakes == balanceOf(unstakingDestination)
   */
  function assert_invariant_B() public {
    // console2.log("sumOfStakerBalances", sumOfStakerBalances);
    // console2.log("cumulativeTotalUnstakesCompleted", cumulativeTotalUnstakesCompleted);
    assertEq(cumulativeTotalUnstakesCompleted, sumOfStakerBalances, "invariant B");
  }

  /**
   * C. Recipient Solvency
   *  sum of recipient balances == cumulative total slashes - unwithdrawn slashed stakes
   */
  function assert_invariant_C() public {
    assertEq(sumOfRecipientBalances, cumulativeTotalSlashes - instance.totalSlashedStakes(), "invariant C");

    assertEq(sumOfStakerSlashes, cumulativeTotalSlashes, "slash measure equivalence");
  }

  /**
   * D. StakingEligibility Solvency
   *  StakingEligibility token balance =
   *    current total stakes
   *  + current total unstakes begun (cooldowns)
   *  + current total slashed stakes
   *  - current total unstakes completed (balances)
   */
  function assert_invariant_D() public {
    assertEq(
      token.balanceOf(address(instance)),
      sumOfStakes // forgefmt: ignore-line
        + sumOfStakerCooldowns // forgefmt: ignore-line
        + instance.totalSlashedStakes() // forgefmt: ignore-line
        - sumOfStakerBalances, // forgefmt: ignore-line
      "invariant D"
    );
  }

  /**
   * E. Global Solvency
   * token supply - stakingHandler balance = current stakes + current unstakes begun (cooldowns) + current slashed
   * stakes +
   * unstakes completed
   * (balances) + current recipient balances
   */
  function assert_invarient_E() public {
    assertEq(
      tokenSupply - token.balanceOf(address(stakingHandler)),
      currentTotalValidStakes + currentTotalUnstakesBegun + instance.totalSlashedStakes()
        + stakingHandler.ghost_cumulativeTotalUnstakesCompleted() + slashingHandler.ghost_cumulativeTotalWithdrawals(),
      "invariant E"
    );
  }
}

contract UnBoundedInvariants is StakingEligibilityInvariantBase {
  function setUp() public virtual override {
    deployDependencies();

    // deploy the handler contracts
    stakingHandler = IStakingHandler(new StakingHandler(instance));
    slashingHandler = ISlashingHandler(new SlashingHandler(instance, stakingHandler));
    adminHandler = IAdminHandler(new AdminHandler(instance));

    // configure the scope
    configureScope();
  }

  /*//////////////////////////////////////////////////////////////
                              TESTS
  //////////////////////////////////////////////////////////////*/

  // Staker Solvency
  function invariant_A_B() public {
    stakers = stakingHandler.stakers();
    for (uint256 i; i < stakers.length; ++i) {
      cumulativeStakerStakes = stakingHandler.ghost_cumulativeStakerStakes(stakers[i]);
      cumulativeStakerSlashes = slashingHandler.ghost_cumulativeStakerSlashes(stakers[i]);
      stakerStakes = stakingHandler.getStakedAmount(stakers[i]);
      stakerCooldowns = stakingHandler.getCooldownAmount(stakers[i]);
      stakerBalance = token.balanceOf(stakers[i]);
      // console2.log("current staker", stakers[i]);
      // console2.log("cumulativeStakerStakes", cumulativeStakerStakes);
      // console2.log("current stakerStakes", stakerStakes);
      // console2.log("current stakerCooldowns", stakerCooldowns);
      // console2.log("current stakerBalance", stakerBalance);
      // console2.log("cumulativeStakerSlashes", cumulativeStakerSlashes);

      assert_invariant_A();

      sumOfStakerBalances += stakerBalance;
    }

    cumulativeTotalUnstakesCompleted = stakingHandler.ghost_cumulativeTotalUnstakesCompleted();

    assert_invariant_B();
  }

  function invariant_C() public {
    stakers = stakingHandler.stakers();
    recipients = slashingHandler.recipients();
    // console2.log("stakers", stakers.length);
    for (uint256 i; i < stakers.length; ++i) {
      sumOfStakerSlashes += slashingHandler.ghost_cumulativeStakerSlashes(stakers[i]);
    }
    for (uint256 i; i < recipients.length; ++i) {
      sumOfRecipientBalances += token.balanceOf(recipients[i]);
    }

    cumulativeTotalSlashes = slashingHandler.ghost_cumulativeTotalSlashes();

    // console2.log("sumOfRecipientBalances", sumOfRecipientBalances);
    // console2.log("ghost_cumulativeTotalSlashes", cumulativeTotalSlashes);
    // console2.log("current totalSlashedStakes", instance.totalSlashedStakes());

    assert_invariant_C();
  }

  function invariant_D() public {
    stakers = stakingHandler.stakers();
    for (uint256 i; i < stakers.length; ++i) {
      sumOfStakerCooldowns += stakingHandler.getCooldownAmount(stakers[i]);
      sumOfStakes += stakingHandler.getStakedAmount(stakers[i]);
    }
    assert_invariant_D();
  }

  function invariant_E() public {
    tokenSupply = stakingHandler.TOKEN_SUPPLY();
    currentTotalValidStakes = stakingHandler.ghost_currentTotalValidStakes();
    currentTotalUnstakesBegun = stakingHandler.ghost_currentTotalUnstakesBegun();
    cumulativeTotalUnstakesCompleted = stakingHandler.ghost_cumulativeTotalUnstakesCompleted();
    cumulativeTotalWithdrawals = slashingHandler.ghost_cumulativeTotalWithdrawals();

    assert_invarient_E();

    callSummary();
  }
}

contract BoundedInvariants is UnBoundedInvariants {
  function setUp() public override {
    deployDependencies();

    // deploy the handler contracts
    stakingHandler = IStakingHandler(new BoundedStakingHandler(instance));
    slashingHandler = ISlashingHandler(new BoundedSlashingHandler(instance, stakingHandler));
    adminHandler = IAdminHandler(new BoundedAdminHandler(instance));

    // configure the scope
    configureScope();
  }
}
