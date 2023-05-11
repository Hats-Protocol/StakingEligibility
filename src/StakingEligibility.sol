// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { HatsEligibilityModule, HatsModule } from "hats-module/HatsEligibilityModule.sol";
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

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a StakingEligibility for `hatId` and `token` is deployed to address `instance`
  event StakingEligibility_Deployed(
    uint256 hatId, address instance, address token, uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat
  );
  /// @notice Emitted when a staker stakes
  event StakingEligibility_Staked(address staker, uint248 amount);
  /// @notice Emitted when a judge slashes a wearer
  event StakingEligibility_Slashed(address wearer, uint248 amount);
  /// @notice Emitted when the minStake is updated by an admin of the {hatId}
  event StakingEligibility_MinStakeChanged(uint248 newMinStake);
  /// @notice Emitted when the judgeHat is updated by an admin of the {hatId}
  event StakingEligibility_JudgeHatChanged(uint256 newJudgeHat);
  /// @notice Emitted when the recipientHat is updated by an admin of the {hatId}
  event StakingEligibility_RecipientHatChanged(uint256 newRecipientHat);

  /*//////////////////////////////////////////////////////////////
                            DATA MODELS
  //////////////////////////////////////////////////////////////*/

  /// @dev Packed into a single storage slot
  /// @custom:member amount The amount of tokens staked
  /// @custom:member slashed Whether the stake has been slashed
  struct Stake {
    uint248 amount; // 31 bytes
    bool slashed; // 1 byte
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
   * 0       | IMPLEMENTATIO   | address | 20      |                     |
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

  /// @notice The stakes of each staker
  mapping(address staker => Stake stake) public stakes;

  /// @notice The sum of all valid stakes
  uint248 public totalValidStakes;

  /// @notice The sum of all slashed stakes that have not been withdrawn
  uint248 public totalSlashedStakes;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @inheritdoc HatsModule
   */
  function setUp(bytes memory _initdata) public override initializer {
    // decode the _initData bytes and set the values in storage
    (uint248 _minStake, uint256 _judgeHat, uint256 _recipientHat) = abi.decode(_initdata, (uint248, uint256, uint256));
    // set the initial values in storage
    minStake = _minStake;
    judgeHat = _judgeHat;
    recipientHat = _recipientHat;

    // log the deployment & setup
    emit StakingEligibility_Deployed(hatId(), address(this), address(TOKEN()), _minStake, _judgeHat, _recipientHat);
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
    Stake storage s = stakes[_wearer];
    // standing is the opposite of slashed
    standing = !s.slashed;

    // wearers are always ineligible if in bad standing, so no need to do another SLOAD if standing==false
    eligible = standing ? s.amount >= minStake : false;
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
    Stake storage s = stakes[msg.sender];
    // staker must have not been slashed
    if (s.slashed) revert StakingEligibility_AlreadySlashed();

    // increment the staker's stake
    s.amount += _amount;
    // increment the total valid stakes
    totalValidStakes += _amount;

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
   * @notice Unstake `_amount` tokens
   * @param _amount The amount of tokens to unstake, as a uint248. Must be less than or equal to the caller's current
   * stake
   */
  function unstake(uint248 _amount) external {
    // load a pointer to the wearer's stake in storage
    Stake storage s = stakes[msg.sender];
    // _staker must have enough tokens staked; can occur after withdrawal or slashing
    if (s.amount < _amount) revert StakingEligibility_InsufficientStake();

    // decrement the staker's stake
    s.amount -= _amount;
    // decrement the total valid stakes
    totalValidStakes -= _amount;

    // execute the unstake,
    bool success = TOKEN().transfer(msg.sender, _amount);
    if (!success) revert StakingEligibility_TransferFailed();
    /**
     * @dev this action is logged by the token contract, so we don't need to emit an event
     *
     * ERC20.Transfer(address(this), _staker, _amount);
     */
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Slash `_staker`'s full stake. Even if stake is 0, slashing still sets their standing to false in
   * {getWearerStatus}
   * @dev Only a wearer of the judge hat can slash; cannot slash twice
   * @param _staker The staker to slash
   */
  function slash(address _staker) external {
    // only the judge can slash
    if (!HATS().isWearerOfHat(msg.sender, judgeHat)) revert StakingEligibility_NotJudge();
    // load a pointer to the wearer's stake in storage
    Stake storage s = stakes[_staker];
    // cannot slash if already slashed
    if (s.slashed) revert StakingEligibility_AlreadySlashed();

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
    emit StakingEligibility_Slashed(_staker, toSlash);
  }

  /**
   * @notice Withdraw all slashed stakes to a wearer of the recipient hat
   * @param _recipient The recipient of the withdrawn tokens; must wear the recipient hat
   */
  function withdraw(address _recipient) external {
    // read the total slashed stakes into memory
    uint248 toWithdraw = totalSlashedStakes;
    // don't proceed if there's nothing to withdraw
    if (toWithdraw == 0) revert StakingEligibility_NothingToWithdraw();
    // can only be withdrawn to the recipient
    if (!HATS().isWearerOfHat(_recipient, recipientHat)) revert StakingEligibility_NotRecipient();

    // we're going to withdraw all of it, so the new value should be 0
    totalSlashedStakes = 0;

    // execute the withdrawal, reverting if the transfer fails
    bool success = TOKEN().transfer(_recipient, toWithdraw);
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

  function changeJudgeHat(uint256 _judgeHat) external onlyHatAdmin hatIsMutable {
    judgeHat = _judgeHat;

    // log the change
    emit StakingEligibility_JudgeHatChanged(_judgeHat);
  }

  function changeRecipientHat(uint256 _recipientHat) external onlyHatAdmin hatIsMutable {
    recipientHat = _recipientHat;

    // log the change
    emit StakingEligibility_RecipientHatChanged(_recipientHat);
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
