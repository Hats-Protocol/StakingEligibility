// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { IHatsEligibility } from "hats-protocol/Interfaces/IHatsEligibility.sol";
import { HatsAccessControl } from "hats-auth/HatsAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingEligibility is IHatsEligibility, HatsAccessControl {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  error InsufficientStake();

  error DuplicateRuling();

  error AlreadySlashed();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  event Staked(address staker, uint248 amount);

  event Slashed(address wearer, uint248 amount);

  /*//////////////////////////////////////////////////////////////
                            DATA MODELS
  //////////////////////////////////////////////////////////////*/

  /// @dev Packed into a single storage slot
  struct Stake {
    uint248 amount; // 31 bytes
    bool slashed; // 1 byte
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC CONSTANTS
  //////////////////////////////////////////////////////////////*/

  IERC20 public immutable token;

  uint248 public immutable minStake;

  // TODO figure out role stuff
  bytes32 public constant JUDGE_ROLE = keccak256("JUDGE_ROLE");
  bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

  /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
  //////////////////////////////////////////////////////////////*/

  mapping(address staker => Stake stake) public stakes;

  uint248 public totalValidStakes;
  uint248 public totalSlashedStakes;

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  constructor(IERC20 _token, uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat) {
    token = _token;
    minStake = _minStake;
    _grantRole(JUDGE_ROLE, _judgeHat);
    _grantRole(RECIPIENT_ROLE, _recipientHat);
  }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    // load a pointer to the wearer's stake in storage
    Stake storage s = stakes[_wearer];
    // standing is the opposite of slashed
    standing = !s.slashed;

    // wearers are always ineligible if in bad standing, so no need to do another SLOAD if standing==false
    eligible = standing ? false : s.amount >= minStake;
  }

  /*//////////////////////////////////////////////////////////////
                            STAKING LOGIC
  //////////////////////////////////////////////////////////////*/

  function stake(address _staker, uint248 _amount) external {
    // checks

    // increment the staker's stake
    stakes[_staker].amount += _amount;
    // increment the total valid stakes
    totalValidStakes += _amount;

    // execute the stake and log it
    token.transferFrom(_staker, address(this), uint256(_amount));
    emit Staked(_staker, _amount);
  }

  function unstake(address _staker, uint248 _amount) external {
    Stake storage s = stakes[_staker];
    // _staker must have enough tokens staked
    if (s.amount < _amount) revert InsufficientStake();
    // _staker cannot unstake if slashed
    if (s.slashed) revert AlreadySlashed();

    // decrement the staker's stake
    s.amount -= _amount;
    // decrement the total valid stakes
    totalValidStakes -= _amount;

    // execute the unstake
    token.transfer(_staker, _amount);
    // this action is logged by the token contract, so we don't need to emit an event
    // ERC20.Transfer(address(this), _staker, _amount);
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
  //////////////////////////////////////////////////////////////*/

  function slash(address _wearer) external {
    // checks
    // TODO only judge role

    // load a pointer to the wearer's stake in storage
    Stake storage s = stakes[_wearer];

    if (s.slashed) revert AlreadySlashed();
    // read the amount to slash into memory
    uint248 toSlash = s.amount;
    // set the status to slashed
    s.slashed = true;
    // we are slashing, so we zero out the stake
    s.amount = 0;
    // decrement the total valid stakes
    totalValidStakes -= toSlash;
    // increment the total slashed stakes
    totalSlashedStakes += toSlash;

    // log the slash
    emit Slashed(_wearer, toSlash);
  }

  function withdraw() external {
    // checks
    // TODO only recipient role

    // read the total slashed stakes into memory
    uint248 toWithdraw = totalSlashedStakes;
    // we're going to withdraw all of it, so the new value should be 0
    totalSlashedStakes = 0;

    // execute the withdrawal
    token.transfer(msg.sender, toWithdraw);
    // this action is logged by the token contract, so we don't need to emit an event
    // ERC20.Transfer(address(this), msg.sender, amount);
  }
}
