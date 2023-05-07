// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { StakingEligibility } from "src/StakingEligibility.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract StakingEligibilityFactory {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted if attempting to deploy a StakingEligibility for a given `hatId` and `token` that already has a
  /// StakingEligibility deployment
  error StakingEligibilityFactory_AlreadyDeployed(uint256 hatId, address token);

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice The address of the StakingEligibility implementation
  StakingEligibility public immutable IMPLEMENTATION;
  /// @notice The address of the Hats Protocol
  IHats public immutable HATS;
  /// @notice The version of this StakingEligibilityFactory
  string public version;

  /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @param _implementation The address of the StakingEligibility implementation
   * @param _version The label for this version of StakingEligibility
   */
  constructor(StakingEligibility _implementation, IHats _hats, string memory _version) {
    IMPLEMENTATION = _implementation;
    HATS = _hats;
    version = _version;
  }

  /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a new StakingEligibility instance for a given `_hatId` to a deterministic address, if not
   * already deployed, and sets up the new instance with initial operational values.
   * @dev Will revert *after* the instance is deployed if their initial values are invalid.
   * @param _hatId The hat for which to deploy a StakingEligibility.
   * @param _token The token to stake
   * @param _minStake The minimum stake required to be eligible for the hat
   * @param _judgeHat The hat that can slash wearers
   * @param _recipientHat The hat that can withdraw slashed stakes the season that must elapse before the branch can be
   * extended
   * for another season. Must be <= 10,000.
   * @return _instance The address of the deployed StakingEligibility instance
   */
  function createStakingEligibility(
    uint256 _hatId,
    address _token,
    uint248 _minStake,
    uint256 _judgeHat,
    uint256 _recipientHat
  ) public returns (StakingEligibility _instance) {
    // check if StakingEligibility has already been deployed for _hatId
    if (deployed(_hatId, _token)) revert StakingEligibilityFactory_AlreadyDeployed(_hatId, _token);
    // deploy the clone to a deterministic address
    _instance = _createStakingEligibility(_hatId, _token);
    // set up the toggle with initial operational values
    _instance.setUp(_minStake, _judgeHat, _recipientHat);
  }

  /**
   * @notice Predicts the address of a StakingEligibility instance for a given hat
   * @param _hatId The hat for which to predict the StakingEligibility instance address
   * @return The predicted address of the deployed instance
   */
  function getStakingEligibilityAddress(uint256 _hatId, address _token) public view returns (address) {
    // prepare the unique inputs
    bytes memory args = _encodeArgs(_hatId, _token);
    bytes32 _salt = _calculateSalt(args);
    // predict the address
    return _getStakingEligibilityAddress(args, _salt);
  }

  /**
   * @notice Checks if a StakingEligibility instance has already been deployed for a given hat
   * @param _hatId The hat for which to check for an existing instance
   * @param _token The token to stake
   * @return True if an instance has already been deployed for the given hat
   */
  function deployed(uint256 _hatId, address _token) public view returns (bool) {
    // check for contract code at the predicted address
    return getStakingEligibilityAddress(_hatId, _token).code.length > 0;
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deployes a new StakingEligibility contract for a given hat, to a deterministic address
   * @param _hatId The hat for which to deploy a StakingEligibility
   * @return _instance The address of the deployed StakingEligibility
   */
  function _createStakingEligibility(uint256 _hatId, address _token) internal returns (StakingEligibility _instance) {
    // encode the Hats contract adddress and _hatId to pass as immutable args when deploying the clone
    bytes memory args = _encodeArgs(_hatId, _token);
    // calculate the determinstic address salt as the hash of the _hatId and the Hats Protocol address
    bytes32 _salt = _calculateSalt(args);
    // deploy the clone to the deterministic address
    _instance = StakingEligibility(LibClone.cloneDeterministic(address(IMPLEMENTATION), args, _salt));
  }

  /**
   * @notice Predicts the address of a StakingEligibility contract given the encoded arguments and salt
   * @param _args The encoded arguments to pass to the clone as immutable storage
   * @param _salt The salt to use when deploying the clone
   * @return The predicted address of the deployed StakingEligibility
   */
  function _getStakingEligibilityAddress(bytes memory _args, bytes32 _salt) internal view returns (address) {
    return LibClone.predictDeterministicAddress(address(IMPLEMENTATION), _args, _salt, address(this));
  }

  /**
   * @notice Encodes the arguments to pass to the clone as immutable storage. The arguments are:
   *  - The address of this factory
   *  - The address of the Hats Protocol
   *  - The`_hatId`
   *  - The `_token`
   * @return The encoded arguments
   */
  function _encodeArgs(uint256 _hatId, address _token) internal view returns (bytes memory) {
    return abi.encodePacked(address(this), HATS, _hatId, _token);
  }

  /**
   * @notice Calculates the salt to use when deploying the clone. The (packed) inputs are:
   *  - The address of the this contract, `FACTORY` (passed as part of `_args`)
   *  - The address of the Hats Protocol, `HATS` (passed as part of `_args`)
   *  - The `_hatId` (passed as part of `_args`)
   *  - The address of the `_token` (passed as part of `_args`)
   *  - The chain ID of the current network, to avoid confusion across networks since the same hat trees
   *    on different networks may have different wearers/admins
   * @param _args The encoded arguments to pass to the clone as immutable storage
   * @return The salt to use when deploying the clone
   */
  function _calculateSalt(bytes memory _args) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(_args, block.chainid));
  }
}
