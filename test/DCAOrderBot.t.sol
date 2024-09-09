// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICreditAccountV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditAccountV3.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {
    ICreditFacadeV3Multicall,
    ALL_CREDIT_FACADE_CALLS_PERMISSION
} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";

import {DCABot} from "../src/DCAOrderBot.sol";
import {BotTestHelper} from "./BotTestHelper.sol";

contract DCAOrderBotTest is BotTestHelper {
    // tested bot
    DCABot public bot;
    ICreditAccountV3 creditAccount;

    // tokens
    IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // actors
    address user;
    address executor;

    function setUp() public {
        user = makeAddr("USER");
        executor = makeAddr("EXECUTOR");

        setUpGearbox("Trade USDC Tier 1");

        creditAccount = openCreditAccount(user, 50_000e6, 100_000e6);

        bot = new DCABot();
        vm.prank(user);
        creditFacade.setBotPermissions(
            address(creditAccount), address(bot), uint192(ALL_CREDIT_FACADE_CALLS_PERMISSION)
        );
    }

    function test_DCA_01_setUp_is_correct() public {
        assertEq(address(underlying), address(usdc), "Incorrect underlying");
        assertEq(creditManager.getBorrowerOrRevert(address(creditAccount)), user, "Incorrect account owner");
        assertEq(usdc.balanceOf(address(creditAccount)), 150_000e6, "Incorrect account balance of underlying");
        assertEq(creditFacade.botList(), address(botList), "Incorrect bot list");
    }

    function test_DCA_02_submitDCAOrder_reverts_if_caller_is_not_borrower() public {
        DCABot.DCAOrder memory dcaOrder;

        vm.expectRevert(DCABot.CallerNotBorrower.selector);
        vm.prank(user);
        bot.submitDCAOrder(dcaOrder);

        address caller = makeAddr("CALLER");
        dcaOrder.borrower = caller;
        dcaOrder.manager = address(creditManager);
        dcaOrder.account = address(creditAccount);

        vm.expectRevert(DCABot.CallerNotBorrower.selector);
        vm.prank(caller);
        bot.submitDCAOrder(dcaOrder);
    }

    function test_DCA_03_submitDCAOrder_works_as_expected_when_called_properly() public {
        DCABot.DCAOrder memory dcaOrder = DCABot.DCAOrder({
            borrower: user,
            manager: address(creditManager),
            account: address(creditAccount),
            tokenIn: address(usdc),
            tokenOut: address(weth),
            amountPerInterval: 200_000e6,
            interval: 1 days,
            nextExecutionTime: block.timestamp + 1 days,
            totalExecutions: 10,
            executionsLeft: 10
        });

        vm.expectEmit(true, true, true, true);
        emit DCABot.CreateDCAOrder(user, 0);

        vm.prank(user);
        uint256 orderId = bot.submitDCAOrder(dcaOrder);
        assertEq(orderId, 0, "Incorrect orderId");

        _assertDCAOrderIsEqual(orderId, dcaOrder);
    }

    function test_DCA_04_cancelDCAOrder_reverts_if_caller_is_not_borrower() public {
        DCABot.DCAOrder memory dcaOrder;
        dcaOrder.borrower = user;
        dcaOrder.manager = address(creditManager);
        dcaOrder.account = address(creditAccount);

        vm.prank(user);
        uint256 orderId = bot.submitDCAOrder(dcaOrder);

        address caller = makeAddr("CALLER");
        vm.expectRevert(DCABot.CallerNotBorrower.selector);
        vm.prank(caller);
        bot.cancelDCAOrder(orderId);
    }

    function test_DCA_05_cancelDCAOrder_works_as_expected_when_called_properly() public {
        DCABot.DCAOrder memory dcaOrder;
        dcaOrder.borrower = user;
        dcaOrder.manager = address(creditManager);
        dcaOrder.account = address(creditAccount);

        vm.prank(user);
        uint256 orderId = bot.submitDCAOrder(dcaOrder);

        vm.expectEmit(true, true, true, true);
        emit DCABot.CancelDCAOrder(user, orderId);

        vm.prank(user);
        bot.cancelDCAOrder(orderId);

        _assertDCAOrderIsEmpty(orderId);
    }

    function _assertDCAOrderIsEqual(uint256 orderId, DCABot.DCAOrder memory dcaOrder) internal {
        (
            address borrower,
            address manager,
            address account,
            address tokenIn,
            address tokenOut,
            uint256 amountPerInterval,
            uint256 interval,
            uint256 nextExecutionTime,
            uint256 totalExecutions,
            uint256 executionsLeft
        ) = bot.dcaOrders(orderId);
        assertEq(borrower, dcaOrder.borrower, "Incorrect borrower");
        assertEq(manager, dcaOrder.manager, "Incorrect manager");
        assertEq(account, dcaOrder.account, "Incorrect account");
        assertEq(tokenIn, dcaOrder.tokenIn, "Incorrect tokenIn");
        assertEq(tokenOut, dcaOrder.tokenOut, "Incorrect tokenOut");
        assertEq(amountPerInterval, dcaOrder.amountPerInterval, "Incorrect amountPerInterval");
        assertEq(interval, dcaOrder.interval, "Incorrect interval");
        assertEq(nextExecutionTime, dcaOrder.nextExecutionTime, "Incorrect nextExecutionTime");
        assertEq(totalExecutions, dcaOrder.totalExecutions, "Incorrect totalExecutions");
        assertEq(executionsLeft, dcaOrder.executionsLeft, "Incorrect executionsLeft");
    }

    function _assertDCAOrderHasRemainingExecutions(uint256 orderId, uint256 expectedExecutionsLeft) internal {
        (, , , , , , , , , uint256 executionsLeft) = bot.dcaOrders(orderId);
        assertEq(executionsLeft, expectedExecutionsLeft, "Incorrect executions left");
    }

    function _assertDCAOrderIsEmpty(uint256 orderId) internal {
        (
            address borrower,
            address manager,
            address account,
            address tokenIn,
            address tokenOut,
            uint256 amountPerInterval,
            uint256 interval,
            uint256 nextExecutionTime,
            uint256 totalExecutions,
            uint256 executionsLeft
        ) = bot.dcaOrders(orderId);
        assertEq(borrower, address(0), "Incorrect borrower");
        assertEq(manager, address(0), "Incorrect manager");
        assertEq(account, address(0), "Incorrect account");
        assertEq(tokenIn, address(0), "Incorrect tokenIn");
        assertEq(tokenOut, address(0), "Incorrect tokenOut");
        assertEq(amountPerInterval, 0, "Incorrect amountPerInterval");
        assertEq(interval, 0, "Incorrect interval");
        assertEq(nextExecutionTime, 0, "Incorrect nextExecutionTime");
        assertEq(totalExecutions, 0, "Incorrect totalExecutions");
        assertEq(executionsLeft, 0, "Incorrect executionsLeft");
    }
}
