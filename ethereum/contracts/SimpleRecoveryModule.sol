pragma solidity ^0.5.0;

import "@gnosis.pm/safe-contracts/contracts/base/Module.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";
import "./external/SafeMath.sol";

contract SimpleRecoveryModule is Module {

    using SafeMath for uint256;

    string public constant NAME = "Simple Recovery Module";
    string public constant VERSION = "1.0.0";

    // Address that can trigger the recovery
    address public recoverer;
    // Recovery duration in seconds
    uint256 public recoveryDurationS;
    // Time when recovery was triggerd
    uint256 public recoveryStartTime;
    // Owners that should be added for recovery;
    address[] public recoveryOwners;

    uint256 public nonce;

    /// @dev Setup function sets initial storage of contract.
    function setup(address _recoverer, uint256 _recoveryDurationS)
        public
    {
        setManager();
        require(_recoverer != address(0), "Invalid recoverer provided");
        recoverer = _recoverer;
        recoveryDurationS = _recoveryDurationS;
    }

    /// @dev Triggers the recovery process, it is required to specify the owners that should be added and sign them.
    /// The signature is generated by signing the hash of the version 0 EIP-161 hash of the new owners and the nonce
    /// @param r - part of the signature
    /// @param s - part of the signature
    /// @param v - part of the signature
    /// @param _recoveryOwners that should be added to the manager with this recovery
    function triggerRecovery(bytes32 r, bytes32 s, uint8 v, address[] memory _recoveryOwners) public {
        require(recoveryStartTime == 0, "Recovery was already started!");
        require(_recoveryOwners.length > 0, "New owners are required!");
        require(recoverer == ecrecover(keccak256(abi.encodePacked(byte(0x19), byte(0x00), _recoveryOwners, nonce)), v, r, s), "Invalid signature provided!");
        nonce = nonce + 1;
        recoveryStartTime = now;
        recoveryOwners = _recoveryOwners;
    }

    /// @dev Executes the recovery. It is required that there are least `recoveryDurationS` seconds between the call to `triggerRecovery` and this method
    function executeRecovery() public {
        require(recoveryStartTime > 0, "Recovery was not triggered yet!");
        require(now >= recoveryStartTime.add(recoveryDurationS), "Recovery cannot be executed yet!");
        recoveryStartTime = 0;
        for (uint256 i = 0; i < recoveryOwners.length; i++) {
            bytes memory addOwnerData = abi.encodeWithSignature("addOwnerWithThreshold(address,uint256)", recoveryOwners[i], recoveryOwners.length);
            require(manager.execTransactionFromModule(address(manager), 0, addOwnerData, Enum.Operation.Call), "Could not execute recovery!");
        }
        delete recoveryOwners;
    }

    /// @dev Triggers the recovery and immediatly execute the recovery. This is only possible if `recoveryDurationS` is 0.
    function triggerAndExecuteRecoveryWithoutDelay(bytes32 r, bytes32 s, uint8 v, address[] memory _recoveryOwners) public {
        require(recoveryDurationS == 0, "This method can only be used if not delay was defined!");
        triggerRecovery(r, s, v, _recoveryOwners);
        executeRecovery();
    }

    /// @dev Cancels the recovery process
    function cancelRecovery() public authorized {
        require(recoverer != address(0), "Module was already used!");
        require(recoveryStartTime > 0, "Recovery was not triggered yet!");
        recoveryStartTime = 0;
        delete recoveryOwners;
    }
}