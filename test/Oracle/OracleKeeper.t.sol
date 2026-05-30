// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {OracleKeeper} from "../../src/Oracle/OracleKeeper.sol";

// ─── Mock oracle ──────────────────────────────────────────────────────────────

contract MockTwapOracle {
    bool public ready;
    uint256 public updateCalls;
    bool public revertOnUpdate;

    function setReady(bool v) external {
        ready = v;
    }

    function setRevertOnUpdate(bool v) external {
        revertOnUpdate = v;
    }

    function updateReady() external view returns (bool) {
        return ready;
    }

    function update() external {
        if (revertOnUpdate) revert("oracle: period not elapsed");
        updateCalls++;
    }
}

// ─── Base harness ─────────────────────────────────────────────────────────────

contract OracleKeeperTest is Test {
    MockTwapOracle internal mockOracle;
    OracleKeeper internal keeper;

    address internal owner = makeAddr("owner");
    address internal forwarder = makeAddr("forwarder");
    address internal anyone = makeAddr("anyone");

    function setUp() public virtual {
        mockOracle = new MockTwapOracle();

        vm.prank(owner);
        keeper = new OracleKeeper(address(mockOracle));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §1  Constructor
// ══════════════════════════════════════════════════════════════════════════════

contract Test_KeeperConstructor is OracleKeeperTest {
    function test_OracleIsSet() public view {
        assertEq(address(keeper.oracle()), address(mockOracle));
    }

    function test_LastTimeStamp_SetToDeployBlock() public view {
        assertEq(keeper.lastTimeStamp(), block.timestamp);
    }

    function test_ForwarderAddress_ZeroInitially() public view {
        assertEq(keeper.forwarderAddress(), address(0));
    }

    function test_Owner_IsDeployer() public view {
        assertEq(keeper.owner(), owner);
    }

    function test_ZeroOracleAddress_Reverts() public {
        vm.expectRevert(OracleKeeper.ZeroAddress.selector);
        new OracleKeeper(address(0));
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §2  checkUpkeep()
// ══════════════════════════════════════════════════════════════════════════════

contract Test_CheckUpkeep is OracleKeeperTest {
    function test_ReturnsFalse_WhenOracleNotReady() public view {
        (bool needed,) = keeper.checkUpkeep("");
        assertFalse(needed);
    }

    function test_ReturnsTrue_WhenOracleReady() public {
        mockOracle.setReady(true);
        (bool needed,) = keeper.checkUpkeep("");
        assertTrue(needed);
    }

    function test_ReturnsFalse_AfterOracleBecomesNotReady() public {
        mockOracle.setReady(true);
        (bool needed,) = keeper.checkUpkeep("");
        assertTrue(needed);

        mockOracle.setReady(false);
        (bool needed2,) = keeper.checkUpkeep("");
        assertFalse(needed2);
    }

    function test_CheckUpkeep_IsViewOnly_DoesNotModifyState() public view {
        uint256 callsBefore = mockOracle.updateCalls();
        keeper.checkUpkeep("");
        assertEq(mockOracle.updateCalls(), callsBefore);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §3  performUpkeep()
// ══════════════════════════════════════════════════════════════════════════════

contract Test_PerformUpkeep is OracleKeeperTest {
    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        keeper.setForwarderAddress(forwarder);
        mockOracle.setReady(true);
    }

    function test_OnlyForwarder_CanPerformUpkeep() public {
        vm.prank(anyone);
        vm.expectRevert(OracleKeeper.NotForwarder.selector);
        keeper.performUpkeep("");
    }

    function test_CallsOracleUpdate() public {
        assertEq(mockOracle.updateCalls(), 0);
        vm.prank(forwarder);
        keeper.performUpkeep("");
        assertEq(mockOracle.updateCalls(), 1);
    }

    function test_UpdatesLastTimeStamp() public {
        uint256 before = keeper.lastTimeStamp();
        vm.warp(block.timestamp + 8 hours);
        vm.prank(forwarder);
        keeper.performUpkeep("");
        assertGt(keeper.lastTimeStamp(), before);
        assertEq(keeper.lastTimeStamp(), block.timestamp);
    }

    function test_EmitsUpkeepPerformedEvent() public {
        vm.expectEmit(false, false, false, true);
        emit OracleKeeper.UpkeepPerformed(block.timestamp);
        vm.prank(forwarder);
        keeper.performUpkeep("");
    }

    function test_Reverts_WhenOracleReverts() public {
        mockOracle.setRevertOnUpdate(true);
        vm.prank(forwarder);
        vm.expectRevert("oracle: period not elapsed");
        keeper.performUpkeep("");
    }

    function test_MultipleUpkeeps_IncrementCallCount() public {
        for (uint256 i; i < 5; ++i) {
            vm.prank(forwarder);
            keeper.performUpkeep("");
        }
        assertEq(mockOracle.updateCalls(), 5);
    }

    function test_Reverts_BeforeForwarderIsSet() public {
        // Deploy a keeper without setting the forwarder first.
        vm.prank(owner);
        OracleKeeper fresh = new OracleKeeper(address(mockOracle));

        vm.prank(forwarder);
        vm.expectRevert(OracleKeeper.NotForwarder.selector);
        fresh.performUpkeep("");
    }

    function test_Owner_CannotPerformUpkeep_Directly() public {
        vm.prank(owner);
        vm.expectRevert(OracleKeeper.NotForwarder.selector);
        keeper.performUpkeep("");
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §4  setForwarderAddress()
// ══════════════════════════════════════════════════════════════════════════════

contract Test_SetForwarderAddress is OracleKeeperTest {
    function test_OnlyOwner_CanSetForwarder() public {
        vm.prank(anyone);
        vm.expectRevert();
        keeper.setForwarderAddress(forwarder);
    }

    function test_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(OracleKeeper.ZeroAddress.selector);
        keeper.setForwarderAddress(address(0));
    }

    function test_SetsForwarderAddress() public {
        vm.prank(owner);
        keeper.setForwarderAddress(forwarder);
        assertEq(keeper.forwarderAddress(), forwarder);
    }

    function test_EmitsForwarderSetEvent() public {
        vm.expectEmit(true, false, false, false);
        emit OracleKeeper.ForwarderSet(forwarder);
        vm.prank(owner);
        keeper.setForwarderAddress(forwarder);
    }

    function test_CanReplaceForwarder() public {
        address newForwarder = makeAddr("newForwarder");
        vm.prank(owner);
        keeper.setForwarderAddress(forwarder);
        vm.prank(owner);
        keeper.setForwarderAddress(newForwarder);
        assertEq(keeper.forwarderAddress(), newForwarder);

        // Old forwarder can no longer perform upkeep.
        mockOracle.setReady(true);
        vm.prank(forwarder);
        vm.expectRevert(OracleKeeper.NotForwarder.selector);
        keeper.performUpkeep("");

        // New forwarder can.
        vm.prank(newForwarder);
        keeper.performUpkeep("");
        assertEq(mockOracle.updateCalls(), 1);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// §5  checkUpkeep / performUpkeep round-trip
// ══════════════════════════════════════════════════════════════════════════════

contract Test_RoundTrip is OracleKeeperTest {
    function setUp() public override {
        super.setUp();
        vm.prank(owner);
        keeper.setForwarderAddress(forwarder);
    }

    function test_CheckThenPerform_WhenReady() public {
        mockOracle.setReady(true);
        (bool needed,) = keeper.checkUpkeep("");
        assertTrue(needed);

        vm.prank(forwarder);
        keeper.performUpkeep("");
        assertEq(mockOracle.updateCalls(), 1);
    }

    function test_CheckAndPerform_WhenNotReady_PerformStillCallsOracle() public {
        // checkUpkeep returns false, but nothing stops performUpkeep from being
        // called — the oracle's own guards are the authoritative protection.
        (bool needed,) = keeper.checkUpkeep("");
        assertFalse(needed);

        // performUpkeep will call oracle.update() regardless.
        // (The oracle itself would revert, but here the mock does not.)
        vm.prank(forwarder);
        keeper.performUpkeep("");
        assertEq(mockOracle.updateCalls(), 1);
    }
}
