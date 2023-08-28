// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule } from "hats-module/HatsEligibilityModule.sol";
// import { HatsModule } from "hats-module/HatsModule.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StakingEligibility
 * @author Haberdasher Labs
 * @notice A Hats Protocol eligibility contract that allows stakers to stake tokens to become eligible for a hat and be
 * slashed if they misbehave
 */
contract StakingEligibility is HatsEligibilityModule {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Thrown when a staker tries to unstake more than they have staked
  error StakingEligibility_InsufficientStake();
  /// @notice Thrown when an unstaker attempts to complete an unstake before the cooldown period has elapsed
  error StakingEligibility_CooldownNotEnded();
  /// @notice Thrown when an unstaker attempts to complete an unstake before beginning a cooldown period
  error StakingEligibility_NoCooldown();
  /// @notice Thrown when a judge tries to slash an already-slashed wearer, or when a slashed staker tries to unstake
  error StakingEligibility_AlreadySlashed();
  /// @notice Thrown when a non-judge tries to slash a wearer
  error StakingEligibility_NotJudge();
  /// @notice Thrown when a withdraw to a non-recipient is attempted
  error StakingEligibility_NotRecipient();
  /// @notice Thrown when a non-admin tries to change the minStake
  error StakingEligibility_NotHatAdmin();
  /// @notice Thrown when a change to the minStake is attempted on an immutable hat
  error StakingEligibility_HatImmutable();
  /// @notice Thrown when a transfer fails
  error StakingEligibility_TransferFailed();
  /// @notice Thrown when a withdraw is attempted when there is nothing to withdraw
  error StakingEligibility_NothingToWithdraw();
  /// @notice Thrown when attempting to forgive an unslashed staker
  error StakingEligibility_NotSlashed();

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a StakingEligibility for `hatId` and `token` is deployed to address `instance`
  event StakingEligibility_Deployed(
    uint256 hatId,
    address instance,
    address token,
    uint248 minStake,
    uint256 judgeHat,
    uint256 recipientHat,
    uint256 cooldownPeriod
  );
  /// @notice Emitted when a staker stakes
  event StakingEligibility_Staked(address staker, uint248 amount);
  /// @notice Emitted when a staker begins an unstake
  event StakingEligibility_UnstakeBegun(address staker, uint248 amount, uint256 cooldownEnd);
  /// @notice Emitted when a judge slashes a wearer
  event StakingEligibility_Slashed(address wearer, uint248 amount);
  /// @notice Emitted when the minStake is updated by an admin of the {hatId}
  event StakingEligibility_MinStakeChanged(uint248 newMinStake);
  /// @notice Emitted when the judgeHat is updated by an admin of the {hatId}
  event StakingEligibility_JudgeHatChanged(uint256 newJudgeHat);
  /// @notice Emitted when the recipientHat is updated by an admin of the {hatId}
  event StakingEligibility_RecipientHatChanged(uint256 newRecipientHat);
  /// @notice Emitted when the cooldownPeriod is updated by an admin of the {hatId}
  event StakingEligibility_CooldownPeriodChanged(uint256 newDelay);
  /// @notice Emitted when a slashed staker is forgiven
  event StakingEligibility_Forgiven(address staker);

  /*//////////////////////////////////////////////////////////////
                            DATA MODELS
  //////////////////////////////////////////////////////////////*/

  /**
   * @dev Packed into a single storage slot
   * @custom:member amount The amount of tokens staked
   * @custom:member slashed Whether the stake has been slashed
   */
  struct Stake {
    uint248 amount; // 31 bytes
    bool slashed; // 1 byte
  }

  /**
   * @notice Data for an unstaking cooldown period
   * @custom:member amount The amount of tokens to be unstaked
   * @custom:member endsAt When the cooldown period ends, in seconds since the epoch
   */
  struct Cooldown {
    uint248 amount;
    uint256 endsAt;
  }

  /*//////////////////////////////////////////////////////////////
                          PUBLIC CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their location.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * --------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                           |
   * --------------------------------------------------------------------|
   * Offset  | Constant        | Type    | Length  |                     |
   * --------------------------------------------------------------------|
   * 0       | IMPLEMENTATION  | address | 20      |                     |
   * 20      | HATS            | address | 20      |                     |
   * 40      | hatId           | uint256 | 32      |                     |
   * 72      | TOKEN           | address | 20      |                     |
   * --------------------------------------------------------------------+
   */

  /**
   * @dev The first three getters are inherited from HatsEligibilityModule
   */
  function TOKEN() public pure returns (IERC20) {
    return IERC20(_getArgAddress(72));
  }

  /*//////////////////////////////////////////////////////////////
                          MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The minimum stake required to be eligible for the hat
  /// @dev This is a uint248 to enable stake amounts to be packed into a single storage slot along with the slashed flag
  uint248 public minStake;

  /// @notice The hat that can slash wearers
  uint256 public judgeHat;

  /// @notice The hat that can withdraw slashed stakes
  uint256 public recipientHat;

  /**
   * @notice The number of seconds that must elapse between beginning an unstake and completing it. This should be set
   *  long enough to give a wearer of the `judgeHat` enough time to slash a misbehaving staker before they can unstk.
   */
  uint256 public cooldownPeriod;

  /// @notice The stakes of each staker
  mapping(address staker => Stake stake) public stakes;

  /// @notice Current unstaking cooldown periods
  mapping(address staker => Cooldown cooldown) public cooldowns;

  /// @notice The sum of all slashed stakes that have not yet been withdrawn to a wearer of the `recipientHat`
  uint248 public totalSlashedStakes;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc HatsModule
   */
  function _setUp(bytes calldata _initdata) internal override {
    // decode the _initData bytes and set the values in storage
    (uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat, uint256 _cooldownPeriod) =
      abi.decode(_initdata, (uint248, uint256, uint256, uint256));
    // set the initial values in storage
    minStake = _minStake;
    judgeHat = _judgeHat;
    recipientHat = _recipientHat;
    cooldownPeriod = _cooldownPeriod;

    // log the deployment & setup
    emit StakingEligibility_Deployed(
      hatId(), address(this), address(TOKEN()), _minStake, _judgeHat, _recipientHat, _cooldownPeriod
    );
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the StakingEligibility implementation contract and set its version
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory _version) HatsModule(_version) { }

  /*//////////////////////////////////////////////////////////////
                      HATS ELIGIBILITY FUNCTION
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc HatsEligibilityModule
   */
  function getWearerStatus(address _wearer, uint256 /* _hatId */ )
    public
    view
    override
    returns (bool eligible, bool standing)
  {
    // load a pointer to the wearer's stake in storage
    Stake storage stk = stakes[_wearer];
    // standing is the opposite of slashed
    standing = !stk.slashed;

    // wearers are always ineligible if in bad standing, so no need to do another SLOAD if standing==false
    eligible = standing ? stk.amount >= minStake : false;
  }

  /*//////////////////////////////////////////////////////////////
                            STAKING LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Stake `_amount` tokens, whether for the first time or to increase an existing stake
   * @dev The staker must have approved this contract to transfer tokens on their behalf
   * @param _amount The amount of tokens to stake, as a uint248
   */
  function stake(uint248 _amount) external {
    // load a pointer to the wearer's stake in storage
    Stake storage stk = stakes[msg.sender];
    // staker must have not been slashed
    if (stk.slashed) revert StakingEligibility_AlreadySlashed();

    // increment the staker's stake
    stk.amount += _amount;

    // execute the stake and log it, reverting if the transfer fails
    bool success = TOKEN().transferFrom(msg.sender, address(this), uint256(_amount));
    if (!success) revert StakingEligibility_TransferFailed();
    /**
     * @dev this action is logged by the token contract, but we can't distinguish between a direct transfer and one
     * triggered by this function, so we need to emit an event
     */
    emit StakingEligibility_Staked(msg.sender, _amount);
  }

  /**
   * @notice Begin the process of unstaking `_amount` tokens by initiating a cooldown period, after which the tokens can
   * be unstaked if the skater is not slashed in the meantime. Once unstaking has begun, it cannot be reversed.
   *  The cooldown period exists to a wearer of the `judgeHat` enough time to slash the staker if they misbehave.
   * @dev Caller must have enough tokens staked, and must not be in the middle of an unstake cooldown.
   * @param _amount The amount of tokens to unstake, as a uint248. If removing amount from the caller's stake brings it
   * under `minStake`, they will immediately become ineligible for {hatId}.
   */
  function beginUnstake(uint248 _amount) external {
    // _staker must have enough tokens staked
    Stake storage stk = stakes[msg.sender];
    if (stk.amount < _amount) revert StakingEligibility_InsufficientStake();
    // cannot begin unstaking if already unstaking
    Cooldown storage cooldown = cooldowns[msg.sender];
    if (cooldown.amount > 0) revert StakingEligibility_CooldownNotEnded();

    // create a new cooldown
    cooldown.amount = _amount;
    uint256 end = block.timestamp + cooldownPeriod;
    cooldown.endsAt = end;

    // decrement the staker's stake and tota valid stakes
    unchecked {
      // should not underflow given the InsufficientStake check above
      stk.amount -= _amount;
    }

    // log the unstake initiation
    emit StakingEligibility_UnstakeBegun(msg.sender, _amount, end);
  }

  /**
   * @notice Complete the process of unstaking for a `_staker` after the `cooldownPeriod` has elapsed
   * @dev Callable by anyone on behalf of the `_staker`. Resets the `_staker`'s cooldown values to 0, and transfers the
   * unstaked funds to them.
   */
  function completeUnstake(address _staker) public {
    // load a pointer to the wearer's stake in storage
    Stake storage stk = stakes[_staker];
    // _staker must not have been slashed since beginning the unstake
    if (stk.slashed) revert StakingEligibility_AlreadySlashed();
    // load a pointer to the wearer's unstake ticket in storage
    Cooldown storage cooldown = cooldowns[_staker];
    uint248 amount = cooldown.amount;
    // cooldown must have been initiated
    if (amount == 0) revert StakingEligibility_NoCooldown();
    // cooldown period must have elapsed
    if (cooldown.endsAt > block.timestamp) revert StakingEligibility_CooldownNotEnded();

    // we are completing the unstake, so we zero out the cooldown
    cooldown.amount = 0;
    cooldown.endsAt = 0;

    // execute the unstake, reverting if the transfer fails
    bool success = TOKEN().transfer(_staker, amount);
    if (!success) revert StakingEligibility_TransferFailed();
    /**
     * @dev this action is logged by the token contract, so we don't need to emit an event
     *
     * ERC20.Transfer(address(this), _staker, _amount);
     */
  }

  /**
   * @notice Complete the process of unstaking one's own stake after the `cooldownPeriod` has elapsed
   */
  function completeUnstake() external {
    completeUnstake(msg.sender);
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Slash `_staker`'s full stk. Even if stake is 0, slashing still sets their standing to false in
   * {getWearerStatus}
   * @dev Only a wearer of the judge hat can slash; cannot slash twice
   * @param _staker The staker to slash
   */
  function slash(address _staker) external {
    // only the judge can slash
    if (!HATS().isWearerOfHat(msg.sender, judgeHat)) revert StakingEligibility_NotJudge();
    // load a pointer to the wearer's stake in storage
    Stake storage stk = stakes[_staker];
    // cannot slash if already slashed
    if (stk.slashed) revert StakingEligibility_AlreadySlashed();

    // load a pointer to the _staker's cooldown in storage
    Cooldown storage cooldown = cooldowns[_staker];

    // read the amounts to slash into memory
    uint248 stakedAmount = stk.amount;
    uint248 toSlash = cooldown.amount + stakedAmount;
    // set the status to slashed
    stk.slashed = true;
    // we are slashing, so we zero out the stake amount and cooldown values
    stk.amount = 0;
    cooldown.amount = 0;
    cooldown.endsAt = 0;

    // increment the total slashed stakes by the total amount to slash
    totalSlashedStakes += toSlash;

    // log the slash
    emit StakingEligibility_Slashed(_staker, toSlash);
  }

  /**
   * @notice Forgive `_slashed`, placing them back in good standing and allowing them to {stake} again
   * @dev Only a wearer of the judge hat can forgive; cannot forgive if not slashed
   * @param _staker The staker to forgive
   */
  function forgive(address _staker) external {
    // only the judge can forgive
    if (!HATS().isWearerOfHat(msg.sender, judgeHat)) revert StakingEligibility_NotJudge();
    // load a pointer to the wearer's stake in storage
    Stake storage stk = stakes[_staker];
    // cannot forgive if not slashed
    if (!stk.slashed) revert StakingEligibility_NotSlashed();

    // set slashed to false
    stk.slashed = false;

    // log the forgiveness
    emit StakingEligibility_Forgiven(_staker);
  }

  /**
   * @notice Withdraw all slashed stakes to a wearer of the recipient hat
   * @param _recipient The recipient of the withdrawn tokens; must wear the recipient hat
   */
  function withdraw(address _recipient) external {
    // read the total slashed stakes into memory
    uint248 toWithdraw = totalSlashedStakes;
    // console2.log("toWithdraw", toWithdraw);
    // don't proceed if there's nothing to withdraw
    if (toWithdraw == 0) revert StakingEligibility_NothingToWithdraw();
    // can only be withdrawn to the recipient
    if (!HATS().isWearerOfHat(_recipient, recipientHat)) revert StakingEligibility_NotRecipient();

    // we're going to withdraw all of it, so the new value should be 0
    totalSlashedStakes = 0;

    // execute the withdrawal, reverting if the transfer fails
    bool success = TOKEN().transfer(_recipient, toWithdraw);
    // console2.log("_recipient balance", TOKEN().balanceOf(_recipient));
    if (!success) revert StakingEligibility_TransferFailed();
    /**
     * @dev this action is logged by the token contract, so we don't need to emit an event
     *
     * ERC20.Transfer(address(this), msg.sender, amount);
     */
  }

  /**
   * @notice Change the minimum stake required to be eligible for the hat
   * @dev Only an admin of the {hatId} can change the minStake, and only if the hat is mutable
   * @param _minStake The new minimum stake
   */
  function changeMinStake(uint248 _minStake) external onlyHatAdmin hatIsMutable {
    minStake = _minStake;

    // log the change
    emit StakingEligibility_MinStakeChanged(_minStake);
  }

  /**
   * @notice Change the hat that can slash wearers
   * @dev Only an admin of the {hatId} can change the judgeHat, and only if the hat is mutable
   * @param _judgeHat The new judge hat
   */
  function changeJudgeHat(uint256 _judgeHat) external onlyHatAdmin hatIsMutable {
    judgeHat = _judgeHat;

    // log the change
    emit StakingEligibility_JudgeHatChanged(_judgeHat);
  }

  /**
   * @notice Change the hat whose wearer is the recipient of withdrawn slashed stakes
   * @dev Only an admin of the {hatId} can change the recipientHat, and only if the hat is mutable
   * @param _recipientHat The new recipient hat
   */
  function changeRecipientHat(uint256 _recipientHat) external onlyHatAdmin hatIsMutable {
    recipientHat = _recipientHat;

    // log the change
    emit StakingEligibility_RecipientHatChanged(_recipientHat);
  }

  /**
   * @notice Change the number of seconds that must elapse between beginning an unstake and completing it. This period
   * should be long enough that a wearer of the `judgeHat` has enough time to slash a misbehaving staker before they can
   * unstk.
   * @dev Only an admin of the {hatId} can change the cooldownPeriod, and only if the hat is mutable
   * @param _cooldownPeriod The new cooldown period
   */
  function changeCooldownPeriod(uint256 _cooldownPeriod) external onlyHatAdmin hatIsMutable {
    cooldownPeriod = _cooldownPeriod;

    // log the change
    emit StakingEligibility_CooldownPeriodChanged(_cooldownPeriod);
  }

  /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @dev Returns whether this instance of StakingEligibility's hatId is mutable
   */
  function _hatIsMutable() internal view returns (bool _isMutable) {
    (,,,,,,, _isMutable,) = HATS().viewHat(hatId());
  }

  /*//////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyHatAdmin() {
    if (!HATS().isAdminOfHat(msg.sender, hatId())) revert StakingEligibility_NotHatAdmin();
    _;
  }

  modifier hatIsMutable() {
    if (!_hatIsMutable()) revert StakingEligibility_HatImmutable();
    _;
  }
}
