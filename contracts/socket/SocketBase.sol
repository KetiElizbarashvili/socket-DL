// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.7;

import "../interfaces/IHasher.sol";
import "../interfaces/ITransmitManager.sol";
import "../interfaces/IExecutionManager.sol";

import "../utils/ReentrancyGuard.sol";
import "./SocketConfig.sol";

abstract contract SocketBase is SocketConfig, ReentrancyGuard {
    IHasher public _hasher__;
    ITransmitManager public _transmitManager__;
    IExecutionManager public _executionManager__;

    uint256 public _chainSlug;

    error InvalidAttester();

    event HasherSet(address hasher_);

    function setHasher(address hasher_) external onlyOwner {
        _hasher__ = IHasher(hasher_);
        emit HasherSet(hasher_);
    }

    // TODO: in discussion
    /**
     * @notice updates transmitManager_
     * @param transmitManager_ address of Transmit Manager
     */
    function setTransmitManager(address transmitManager_) external onlyOwner {
        _transmitManager__ = ITransmitManager(transmitManager_);
        emit TransmitManagerSet(transmitManager_);
    }
}
