// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Setup.t.sol";

contract TransmitManagerTest is Setup {
    GasPriceOracle internal gasPriceOracle;

    address public constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    uint256 chainSlug = uint32(uint256(0x2013AA263));
    uint256 destChainSlug = uint32(uint256(0x2013AA264));
    uint256 chainSlug2 = uint32(uint256(0x2113AA263));

    uint256 immutable ownerPrivateKey = c++;
    address owner;

    uint256 immutable transmitterPrivateKey = c++;
    address transmitter;

    uint256 immutable nonTransmitterPrivateKey = c++;
    address nonTransmitter;

    uint256 immutable feesPayerPrivateKey = c++;
    address feesPayer;

    uint256 immutable feesWithdrawerPrivateKey = c++;
    address feesWithdrawer;

    uint256 sealGasLimit = 200000;
    uint256 proposeGasLimit = 100000;
    uint256 sourceGasPrice = 1200000;
    uint256 relativeGasPrice = 1100000;

    uint256 gasPriceOracleNonce;

    SignatureVerifier internal signatureVerifier;
    TransmitManager internal transmitManager;

    event SealGasLimitSet(uint256 gasLimit_);
    event ProposeGasLimitSet(uint256 dstChainSlug_, uint256 gasLimit_);
    event TransmitManagerUpdated(address transmitManager);
    error TransmitterNotFound();
    error InsufficientTransmitFees();
    event FeesWithdrawn(address account_, uint256 value_);
    event SignatureVerifierSet(address signatureVerifier_);

    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        transmitter = vm.addr(transmitterPrivateKey);
        nonTransmitter = vm.addr(nonTransmitterPrivateKey);
        feesPayer = vm.addr(feesPayerPrivateKey);
        feesWithdrawer = vm.addr(feesWithdrawerPrivateKey);

        gasPriceOracle = new GasPriceOracle(owner, chainSlug);
        signatureVerifier = new SignatureVerifier();
        transmitManager = new TransmitManager(
            signatureVerifier,
            gasPriceOracle,
            owner,
            chainSlug,
            sealGasLimit
        );

        vm.startPrank(owner);
        gasPriceOracle.setTransmitManager(transmitManager);
        transmitManager.grantRoleWithUint(chainSlug, transmitter);
        transmitManager.grantRoleWithUint(destChainSlug, transmitter);

        vm.expectEmit(false, false, false, true);
        emit SealGasLimitSet(sealGasLimit);
        transmitManager.setSealGasLimit(sealGasLimit);

        vm.expectEmit(false, false, false, true);
        emit ProposeGasLimitSet(destChainSlug, proposeGasLimit);
        transmitManager.setProposeGasLimit(destChainSlug, proposeGasLimit);

        vm.stopPrank();

        bytes32 digest = keccak256(
            abi.encode(chainSlug, gasPriceOracleNonce, sourceGasPrice)
        );
        bytes memory sig = _createSignature(digest, transmitterPrivateKey);

        gasPriceOracle.setSourceGasPrice(
            gasPriceOracleNonce++,
            sourceGasPrice,
            sig
        );

        digest = keccak256(
            abi.encode(destChainSlug, gasPriceOracleNonce, relativeGasPrice)
        );

        sig = _createSignature(digest, transmitterPrivateKey);

        gasPriceOracle.setRelativeGasPrice(
            destChainSlug,
            gasPriceOracleNonce++,
            relativeGasPrice,
            sig
        );
    }

    function testGenerateAndVerifySignature() public {
        uint256 packetId = 123;
        bytes32 root = bytes32(abi.encode(123));
        bytes32 digest = keccak256(abi.encode(chainSlug, packetId, root));
        bytes memory sig = _createSignature(digest, transmitterPrivateKey);

        address transmitterDecoded = signatureVerifier.recoverSigner(
            chainSlug,
            packetId,
            root,
            sig
        );

        assertEq(transmitter, transmitterDecoded);
    }

    function testCheckTransmitter() public {
        uint256 packetId = 123;
        bytes32 root = bytes32(abi.encode(123));
        bytes32 digest = keccak256(abi.encode(chainSlug, packetId, root));

        bytes memory sig = _createSignature(digest, transmitterPrivateKey);

        (address transmitter_Rsp, bool isTransmitter) = transmitManager
            .checkTransmitter(
                chainSlug,
                keccak256(abi.encode(chainSlug, packetId, root)),
                sig
            );
        assertEq(transmitter_Rsp, transmitter);
        assertTrue(isTransmitter);
    }

    function testGetMinFees() public {
        uint256 minFees = transmitManager.getMinFees(destChainSlug);

        // sealGasLimit * sourceGasPrice + proposeGasLimit * relativeGasPrice
        uint256 minFees_Expected = sealGasLimit *
            sourceGasPrice +
            proposeGasLimit *
            relativeGasPrice;

        assertEq(minFees, minFees_Expected);
    }

    function testPayFees() public {
        uint256 minFees = transmitManager.getMinFees(destChainSlug);
        deal(feesPayer, minFees);

        hoax(feesPayer);
        transmitManager.payFees{value: minFees}(destChainSlug);

        assertEq(address(transmitManager).balance, minFees);
    }

    function testPayInsufficientFees() public {
        uint256 minFees = transmitManager.getMinFees(destChainSlug);
        deal(feesPayer, minFees);

        vm.startPrank(feesPayer);
        vm.expectRevert(InsufficientTransmitFees.selector);
        transmitManager.payFees{value: minFees - 1e4}(destChainSlug);
        vm.stopPrank();
    }

    function testWithdrawFees() public {
        uint256 minFees = transmitManager.getMinFees(destChainSlug);
        deal(feesPayer, minFees);

        vm.startPrank(feesPayer);
        transmitManager.payFees{value: minFees}(destChainSlug);
        vm.stopPrank();

        vm.startPrank(owner);
        vm.expectEmit(false, false, false, true);
        emit FeesWithdrawn(feesWithdrawer, minFees);
        transmitManager.withdrawFees(feesWithdrawer);
        vm.stopPrank();

        assertEq(feesWithdrawer.balance, minFees);
    }

    function testWithdrawFeesToZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert();
        transmitManager.withdrawFees(address(0));
        vm.stopPrank();
    }

    function testGrantTransmitterRole() public {
        assertFalse(
            transmitManager.hasRoleWithUint(chainSlug2, nonTransmitter)
        );

        vm.startPrank(owner);
        transmitManager.grantRoleWithUint(chainSlug2, nonTransmitter);
        vm.stopPrank();

        assertTrue(transmitManager.hasRoleWithUint(chainSlug2, nonTransmitter));
    }

    function testRevokeTransmitterRole() public {
        assertFalse(
            transmitManager.hasRoleWithUint(chainSlug2, nonTransmitter)
        );

        vm.startPrank(owner);
        transmitManager.grantRoleWithUint(chainSlug2, nonTransmitter);
        vm.stopPrank();

        assertTrue(transmitManager.hasRoleWithUint(chainSlug2, nonTransmitter));

        vm.startPrank(owner);
        transmitManager.revokeRoleWithUint(chainSlug2, nonTransmitter);
        vm.stopPrank();

        assertFalse(
            transmitManager.hasRoleWithUint(chainSlug2, nonTransmitter)
        );
    }

    function testSetSignatureVerifier() public {
        SignatureVerifier signatureVerifierNew = new SignatureVerifier();

        hoax(owner);
        vm.expectEmit(false, false, false, true);
        emit SignatureVerifierSet(address(signatureVerifierNew));
        transmitManager.setSignatureVerifier(address(signatureVerifierNew));

        assertEq(
            address(transmitManager.signatureVerifier__()),
            address(signatureVerifierNew)
        );
    }

    function testRescueNativeFunds() public {
        uint256 amount = 1e18;

        assertEq(address(transmitManager).balance, 0);
        deal(address(transmitManager), amount);
        assertEq(address(transmitManager).balance, amount);

        hoax(owner);

        transmitManager.rescueFunds(
            NATIVE_TOKEN_ADDRESS,
            feesWithdrawer,
            amount
        );

        assertEq(feesWithdrawer.balance, amount);
        assertEq(address(transmitManager).balance, 0);
    }
}
