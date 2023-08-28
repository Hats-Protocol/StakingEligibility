// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, DSTest, TestBase, StdCheats, StdUtils } from "forge-std/Test.sol";
import { StakingEligibility, IERC20 } from "src/StakingEligibility.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { AddressSet, LibAddressSet } from "test/handlers/LibHandler.sol";
import { ISlashingHandler } from "test/handlers/SlashingHandler.sol";

interface IStakingHandler {
  function stake(uint248 _amount) external;
  function beginUnstake(uint248 _amount, uint256 _stakerIndexSeed) external;
  function completeUnstake(uint256 _skip, uint256 _stakerIndexSeed) external;
  function setUp(ISlashingHandler _sh) external;
  function TOKEN_SUPPLY() external returns (uint256);
  function numCalls(bytes32 _func) external returns (uint256);
  function ghost_cumulativeTotalStakes() external returns (uint256);
  function ghost_cumulativeTotalUnstakesCompleted() external returns (uint256);
  function ghost_cumulativeStakerStakes(address _staker) external returns (uint256);
  function ghost_currentTotalValidStakes() external returns (uint256);
  function ghost_currentTotalUnstakesBegun() external returns (uint256);
  function getStakedAmount(address _staker) external returns (uint248);
  function getCooldownAmount(address _staker) external returns (uint248);
  function stakers() external returns (address[] memory);
  function isStaker(address _staker) external returns (bool);
  function decrementCurrentTotalValidStakes(uint256 _amount) external;
  function decrementCurrentTotalUnstakesBegun(uint256 _amount) external;
}

contract StakingHandler is IStakingHandler, TestBase, DSTest, StdCheats, StdUtils {
  using LibAddressSet for AddressSet;

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  StakingEligibility public immutable se;
  IERC20 public immutable TOKEN;
  IHats public immutable HATS;
  uint256 public constant TOKEN_SUPPLY = 1_000_000_000 ether; // TOKEN.decimals() = 18

  ISlashingHandler public sh;

  /*//////////////////////////////////////////////////////////////
                            GHOST VARS
  //////////////////////////////////////////////////////////////*/

  // call tracker
  mapping(bytes32 => uint256) public numCalls;

  // cumulative
  uint256 public ghost_cumulativeTotalStakes;
  // uint256 public ghost_cumulativeTotalUnstakesBegun;
  uint256 public ghost_cumulativeTotalUnstakesCompleted;
  mapping(address staker => uint256 staked) public ghost_cumulativeStakerStakes;
  // current
  uint256 public ghost_currentTotalValidStakes;
  uint256 public ghost_currentTotalUnstakesBegun;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR & SETUP
  //////////////////////////////////////////////////////////////*/

  constructor(StakingEligibility _se) {
    se = _se;
    TOKEN = se.TOKEN();
    HATS = se.HATS();
    deal(address(TOKEN), address(this), TOKEN_SUPPLY);
  }

  function setUp(ISlashingHandler _sh) public {
    sh = _sh;
  }

  /*//////////////////////////////////////////////////////////////
                          STAKER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function stake(uint248 _amount) public virtual countCall createStaker {
    // fund the caller
    _pay(currentStaker, _amount);

    // get the caller's prior balance
    uint256 balanceBefore = TOKEN.balanceOf(address(currentStaker));

    // prank as the caller
    vm.startPrank(currentStaker);
    // approve token transfer
    TOKEN.approve(address(se), _amount);
    // stake as the caller
    se.stake(_amount);
    // stop prank
    vm.stopPrank();

    console2.log("stake amount", _amount);

    // get the caller's post balance
    uint256 balanceAfter = TOKEN.balanceOf(address(currentStaker));
    // caller's balance should have decreased by the amount staked
    assertEq(balanceAfter, balanceBefore - _amount, "stake() transferred incorrect amount");

    // update ghost vars
    ghost_currentTotalValidStakes += _amount;
    ghost_cumulativeTotalStakes += _amount;
    ghost_cumulativeStakerStakes[currentStaker] += _amount;
  }

  function beginUnstake(uint248 _amount, uint256 _stakerIndexSeed) public virtual countCall useStaker(_stakerIndexSeed) {
    // begin unstake for the caller
    vm.prank(currentStaker);
    se.beginUnstake(_amount);

    console2.log("begin unstake amount", _amount);
    // update current ghost vars
    ghost_currentTotalValidStakes -= _amount;
    ghost_currentTotalUnstakesBegun += _amount;
    // update cumulative ghost vars
  }

  function completeUnstake(uint256 _skip, uint256 _stakerIndexSeed)
    public
    virtual
    countCall
    useStaker(_stakerIndexSeed)
  {
    // calculate amount to unstake for ghost var update
    (uint248 amount,) = se.cooldowns(currentStaker);

    // get the staker's prior balance
    uint256 balanceBefore = TOKEN.balanceOf(address(currentStaker));

    // skip ahead to the end of the cooldown period
    skip(_skip);
    // complete unstake from caller
    vm.prank(msg.sender);
    se.completeUnstake(currentStaker);

    // get the staker's post balance
    uint256 balanceAfter = TOKEN.balanceOf(address(currentStaker));
    // caller's balance should have decreased by the amount staked
    assertEq(balanceAfter, balanceBefore + amount, "completeUnstake() transferred incorrect amount");

    // update current ghost vars
    ghost_currentTotalUnstakesBegun -= amount;
    // update cumulative ghost vars
    ghost_cumulativeTotalUnstakesCompleted += amount;

    console2.log("complete unstake amount", amount);
  }

  /*//////////////////////////////////////////////////////////////
                              GETTERS
  //////////////////////////////////////////////////////////////*/

  function _getSlashAmounts(address _staker) internal view returns (uint248 total, uint248 fromUnstaked) {
    uint248 staked = getStakedAmount(_staker);
    fromUnstaked = getCooldownAmount(_staker);
    total = staked + fromUnstaked;
  }

  function _pay(address _to, uint256 _amount) internal {
    bool success = TOKEN.transfer(_to, _amount);
    require(success, "_pay() failed");
  }

  function getStakedAmount(address _staker) public view returns (uint248 _amount) {
    (_amount,) = se.stakes(_staker);
  }

  function getCooldownAmount(address _staker) public view returns (uint248 _amount) {
    (_amount,) = se.cooldowns(_staker);
  }

  function stakers() public view returns (address[] memory) {
    return _stakers.addrs;
  }

  /*//////////////////////////////////////////////////////////////
                         PUBLIC SETTERS
  //////////////////////////////////////////////////////////////*/

  /// @dev ensure these are not included in the test call scope

  function decrementCurrentTotalValidStakes(uint256 _amount) public {
    ghost_currentTotalValidStakes -= _amount;
  }

  function decrementCurrentTotalUnstakesBegun(uint256 _amount) public {
    ghost_currentTotalUnstakesBegun -= _amount;
  }

  /*//////////////////////////////////////////////////////////////
                            ACTOR MGMT
  //////////////////////////////////////////////////////////////*/

  AddressSet internal _stakers;
  address internal currentStaker;

  modifier createStaker() {
    currentStaker = msg.sender;
    /// @dev make sure the staker is not a recipient or the staking handler so that we can use staker balances to track
    /// completed unstakes
    require(!sh.isRecipient(currentStaker), "staker should not be a recipient");
    require(currentStaker != address(this), "staker should not be the stakingHandler");
    console2.log("current staker", currentStaker);
    _stakers.add(currentStaker);
    _;
  }

  modifier useStaker(uint256 stakerIndexSeed) {
    address[] memory stakers_ = stakers();
    require(stakers_.length > 0, "no stakers");
    currentStaker = stakers_[bound(stakerIndexSeed, 0, stakers_.length - 1)];
    console2.log("current staker", currentStaker);
    _;
  }

  function isStaker(address _account) public view returns (bool) {
    return _stakers.contains(_account);
  }

  /*//////////////////////////////////////////////////////////////
                            CALL ACCOUNTING
  //////////////////////////////////////////////////////////////*/

  modifier countCall() {
    numCalls[msg.sig]++;
    _;
  }
}

contract BoundedStakingHandler is StakingHandler {
  using LibAddressSet for AddressSet;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR & SETUP
  //////////////////////////////////////////////////////////////*/

  constructor(StakingEligibility _se) StakingHandler(_se) { }

  /*//////////////////////////////////////////////////////////////
                          STAKER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function stake(uint248 _amount) public override countCall createStaker {
    // bound to remaining outstanding tokens
    _amount = uint248(bound(_amount, 0, TOKEN.balanceOf(address(this))));

    super.stake(_amount);
  }

  function beginUnstake(uint248 _amount, uint256 _stakerIndexSeed)
    public
    override
    countCall
    useStaker(_stakerIndexSeed)
  {
    // bound to staker staked amount
    _amount = uint248(bound(_amount, 0, getStakedAmount(currentStaker)));

    super.beginUnstake(_amount, _stakerIndexSeed);
  }

  function completeUnstake(uint256 _skip, uint256 _stakerIndexSeed)
    public
    override
    countCall
    useStaker(_stakerIndexSeed)
  {
    // bound _skipTime to surrounding the cooldown period, weighted in favor of post-cooldown
    _skip = bound(_skip, se.cooldownPeriod() - 10, se.cooldownPeriod() + 1000);

    super.completeUnstake(_skip, _stakerIndexSeed);
  }
}
