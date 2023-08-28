// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2, DSTest, TestBase, StdCheats, StdUtils } from "forge-std/Test.sol";
import { StakingEligibility, IERC20 } from "src/StakingEligibility.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { AddressSet, LibAddressSet } from "test/handlers/LibHandler.sol";
import { IStakingHandler } from "test/handlers/StakingHandler.sol";

interface ISlashingHandler {
  function slash(uint256 _stakerIndexSeed) external;
  function withdraw(address _to) external;
  function recipients() external view returns (address[] memory);
  function getStakedAmount(address _staker) external view returns (uint248 _amount);
  function getCooldownAmount(address _staker) external view returns (uint248 _amount);
  function numCalls(bytes32 _func) external view returns (uint256);
  function ghost_cumulativeTotalSlashes() external view returns (uint256);
  function ghost_cumulativeTotalWithdrawals() external view returns (uint256);
  function ghost_cumulativeStakerSlashes(address staker) external view returns (uint256);
  function isRecipient(address _recipient) external view returns (bool);
}

contract SlashingHandler is ISlashingHandler, TestBase, DSTest, StdCheats, StdUtils {
  using LibAddressSet for AddressSet;

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  StakingEligibility public immutable se;
  IStakingHandler public immutable sh;
  IERC20 public immutable TOKEN;
  IHats public immutable HATS;
  // address public immutable recipientDest;

  /*//////////////////////////////////////////////////////////////
                            GHOST VARS
  //////////////////////////////////////////////////////////////*/

  // call tracker
  mapping(bytes32 => uint256) public numCalls;

  // cumulative
  uint256 public ghost_cumulativeTotalSlashes;
  uint256 public ghost_cumulativeTotalWithdrawals;
  mapping(address staker => uint256 slashed) public ghost_cumulativeStakerSlashes;
  // current

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(StakingEligibility _se, IStakingHandler _sh) {
    se = _se;
    sh = _sh;
    TOKEN = se.TOKEN();
    HATS = se.HATS();

    // add slashingHandler to stakingHandler
    sh.setUp(ISlashingHandler(address(this)));
  }

  /*//////////////////////////////////////////////////////////////
                          JUDGE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function slash(uint256 _stakerIndexSeed) public virtual countCall useStaker(_stakerIndexSeed) {
    // calculate amount to slash to for ghost var update
    (uint248 totalSlashed, uint248 unstakesSlashed) = _getSlashAmounts(currentStaker);

    // attempt to slash the staker
    vm.prank(msg.sender);
    se.slash(currentStaker);

    console2.log("slash amount", totalSlashed);

    // record the slash for this staker and all stakers
    ghost_cumulativeStakerSlashes[currentStaker] += totalSlashed;
    ghost_cumulativeTotalSlashes += totalSlashed;
    // update staking ghost vars
    sh.decrementCurrentTotalValidStakes(totalSlashed - unstakesSlashed); // from stakes
    sh.decrementCurrentTotalUnstakesBegun(unstakesSlashed);
    // sh.decrementCumulativeStakerStakes(currentStaker, totalSlashed); // from stakes
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function withdraw(address _to) public virtual countCall createRecipient(_to) {
    // calculate amount to withdraw for ghost var update
    uint248 amount = se.totalSlashedStakes();
    // get the recipients prior balance
    uint256 balanceBefore = TOKEN.balanceOf(_to);
    console2.log("recipient balance before", balanceBefore);

    // have the msg.sender call withdraw
    vm.prank(msg.sender);
    se.withdraw(_to);

    // get the recipient's new balance
    uint256 balanceAfter = TOKEN.balanceOf(_to);
    console2.log("recipient balance after", balanceAfter);
    // the balance should have changed by the amount withdrawn
    assertEq(balanceAfter, balanceBefore + amount, "withdrawn amount matches recipient balance delta");

    // console2.log("C; _to balance", TOKEN.balanceOf(_to));
    // console2.log("withdraw amount", amount);
    // update cumulative ghost vars
    ghost_cumulativeTotalWithdrawals += amount;
    console2.log("withdraw amount", amount);
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

  function recipients() public view returns (address[] memory) {
    return _recipients.addrs;
  }

  /*//////////////////////////////////////////////////////////////
                            ACTOR MGMT
  //////////////////////////////////////////////////////////////*/

  address internal currentStaker;

  AddressSet internal _recipients;
  address internal currentRecipient;

  modifier useStaker(uint256 stakerIndexSeed) {
    address[] memory stakers_ = sh.stakers();
    vm.assume(stakers_.length > 0);
    currentStaker = stakers_[bound(stakerIndexSeed, 0, stakers_.length - 1)];
    console2.log("current staker", currentStaker);
    _;
  }

  modifier createRecipient(address recipient) {
    /// @dev make sure the recipient is not a staker or the staking handler contract so that we can use staker balances
    /// to track completed unstakes
    require(!sh.isStaker(recipient), "recipient should not be a staker");
    require(recipient != address(sh), "recipient should not be the stakingHandler");
    currentRecipient = recipient;
    console2.log("current recipient", currentRecipient);
    _recipients.add(currentRecipient);
    _;
  }

  function isRecipient(address _account) public view returns (bool) {
    return _recipients.contains(_account);
  }

  /*//////////////////////////////////////////////////////////////
                            CALL ACCOUNTING
  //////////////////////////////////////////////////////////////*/

  modifier countCall() {
    numCalls[msg.sig]++;
    _;
  }
}

contract BoundedSlashingHandler is SlashingHandler {
  using LibAddressSet for AddressSet;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(StakingEligibility _se, IStakingHandler _sh) SlashingHandler(_se, _sh) { }

  /*//////////////////////////////////////////////////////////////
                          JUDGE FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function slash(uint256 _stakerIndexSeed) public override countCall useStaker(_stakerIndexSeed) {
    // mock msg.sender as the judge
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isWearerOfHat.selector, msg.sender, se.judgeHat()), abi.encode(true)
    );

    super.slash(_stakerIndexSeed);
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function withdraw(address _to) public override countCall createRecipient(_to) {
    // mock _to as a recipient
    vm.mockCall(
      address(HATS), abi.encodeWithSelector(IHats.isWearerOfHat.selector, _to, se.recipientHat()), abi.encode(true)
    );

    super.withdraw(_to);
  }
}
