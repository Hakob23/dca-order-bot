// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Balance} from "@gearbox-protocol/core-v2/contracts/libraries/Balances.sol";
import {MultiCall} from "@gearbox-protocol/core-v2/contracts/libraries/MultiCall.sol";
import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {ICreditFacadeV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3.sol";
import {ICreditFacadeV3Multicall} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditFacadeV3Multicall.sol";
import {IPriceOracleV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPriceOracleV3.sol";
import {DCAOrderToken} from "./DCAOrderToken.sol";
import {DCAOrderLib} from "./DCAOrderLib.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Dollar Cost Averaging (DCA) bot.
contract DCAOrderBot is Ownable(msg.sender) {
    using DCAOrderLib for DCAOrderLib.DCAOrder;

    // Reference to the DCAOrderToken contract
    DCAOrderToken public orderToken;

    /// @dev DCA orders counter. This keeps track of the ID of the next DCA order.
    uint256 internal _nextDCAOrderId;

    // ------ //
    // EVENTS //
    // ------ //

    /// @notice Emitted when a user submits a new DCA order.
    /// @param user The user that submitted the order.
    /// @param orderId ID of the created DCA order.
    event CreateDCAOrder(address indexed user, uint256 indexed orderId);

    /// @notice Emitted when a user cancels a DCA order.
    /// @param user The user who canceled the order.
    /// @param orderId ID of the canceled order.
    event CancelDCAOrder(address indexed user, uint256 indexed orderId);

    /// @notice Emitted when a DCA order is successfully executed.
    /// @param executor Account that executed the DCA order.
    /// @param orderId ID of the executed DCA order.
    event ExecuteDCAOrder(address indexed executor, uint256 indexed orderId);

    // ------ //
    // ERRORS //
    // ------ //

    /// @notice Thrown when a user tries to submit or cancel another user's DCA order.
    error CallerNotBorrower();

    /// @notice Thrown when trying to execute a canceled order.
    error OrderIsCancelled();

    /// @notice Thrown when a DCA order can't be executed because it is invalid.
    error InvalidOrder();

    /// @notice Thrown when trying to execute a DCA order before the interval has passed.
    error NotTimeYet();

    /// @notice Thrown when a DCA order has no more executions left.
    error NoExecutionsLeft();

    /// @notice Thrown when the user has insufficient tokens to sell.
    error NothingToSell();

    // Constructor to deploy the DCAOrderToken contract
    constructor() {
        _deployNewOrderToken();
    }

    // ------------------ //
    // EXTERNAL FUNCTIONS //
    // ------------------ //

    /// @notice Allows the owner to deploy a new DCAOrderToken contract and update the reference.
    function deployNewOrderToken() external onlyOwner {
        _deployNewOrderToken();
    }

    /// @notice Submit a new DCA order.
    /// @param dcaOrder The DCA order to submit.
    /// @return orderId The ID of the created DCA order.
    function submitDCAOrder(DCAOrderLib.DCAOrder calldata dcaOrder) external returns (uint256 orderId) {
        // Ensure the caller is the borrower and the borrower is the current owner of the Gearbox account.
        if (
            dcaOrder.borrower != msg.sender
                || ICreditManagerV3(dcaOrder.manager).getBorrowerOrRevert(dcaOrder.account) != dcaOrder.borrower
        ) {
            revert CallerNotBorrower();
        }

        // Generate a new order ID and mint a new ERC721 token representing the order.
        orderId = _useDCAOrderId();
        orderToken.mint(msg.sender, orderId, dcaOrder);

        // Emit an event notifying the DCA order has been created.
        emit CreateDCAOrder(msg.sender, orderId);
    }

    /// @notice Cancel a pending DCA order.
    /// @param orderId ID of the DCA order to cancel.
    function cancelDCAOrder(uint256 orderId) external {
        // Ensure the caller is the owner of the ERC721 token
        if (orderToken.ownerOf(orderId) != msg.sender) {
            revert CallerNotBorrower();
        }

        // Burn the ERC721 token and delete the order data
        orderToken.burn(orderId);

        // Emit an event notifying the DCA order has been cancelled
        emit CancelDCAOrder(msg.sender, orderId);
    }

    /// @notice Execute a DCA order.
    /// @param orderId ID of the DCA order to execute.
    function executeDCAOrder(uint256 orderId) external {

        // Get the DCA order data from the ERC721 contract
        DCAOrderLib.DCAOrder memory dcaOrder = orderToken.getOrder(orderId);

        // Validate the DCA order and get the amount to be exchanged.
        (uint256 amountIn, uint256 minAmountOut) = _validateDCAOrder(dcaOrder);

        // The executor sends the `tokenOut` to the contract and approves the manager.
        IERC20(dcaOrder.tokenOut).transferFrom(msg.sender, address(this), minAmountOut);
        IERC20(dcaOrder.tokenOut).approve(dcaOrder.manager, minAmountOut + 1);

        // Get the facade of the Gearbox credit manager to perform the multicall.
        address facade = ICreditManagerV3(dcaOrder.manager).creditFacade();

        // Create the multi-call for adding and withdrawing collateral using the DCA details.
        MultiCall[] memory calls = new MultiCall[](2);
        calls[0] = MultiCall({
            target: facade,
            callData: abi.encodeCall(ICreditFacadeV3Multicall.addCollateral, (dcaOrder.tokenOut, minAmountOut))
        });
        calls[1] = MultiCall({
            target: facade,
            callData: abi.encodeCall(ICreditFacadeV3Multicall.withdrawCollateral, (dcaOrder.tokenIn, amountIn, msg.sender))
        });
        ICreditFacadeV3(facade).botMulticall(dcaOrder.account, calls);

        // Update the DCA order for the next execution and decrease the executions left.
        dcaOrder.executionsLeft -= 1;
        dcaOrder.nextExecutionTime += dcaOrder.interval;

        if (dcaOrder.executionsLeft == 0) {
            // If no executions are left, burn the token
            orderToken.burn(orderId);
        } else {
            // Update the order data in the ERC721 contract
            orderToken.updateOrder(orderId, dcaOrder);
        }

        // Emit an event notifying that the DCA order has been executed.
        emit ExecuteDCAOrder(msg.sender, orderId);
    }

    function getDCAOrder(uint256 orderId) external view returns (DCAOrderLib.DCAOrder memory dcaOrder) {
        dcaOrder = orderToken.getOrder(orderId);
    }

    // ------------------ //
    // INTERNAL FUNCTIONS //
    // ------------------ //

    /// @dev Deploys a new DCAOrderToken contract and updates the reference.
    function _deployNewOrderToken() internal {
        orderToken = new DCAOrderToken();
        // Transfer ownership of the DCAOrderToken contract to this contract
        orderToken.transferOwnership(address(this));
    }

    /// @dev Increments the DCA order counter and returns its previous value.
    function _useDCAOrderId() internal returns (uint256 orderId) {
        orderId = _nextDCAOrderId;
        _nextDCAOrderId += 1;
    }

    /// @dev Validates the DCA order and ensures it can be executed.
    /// @param dcaOrder The DCA order to validate.
    /// @return amountIn The amount of `tokenIn` to be exchanged in this execution.
    /// @return minAmountOut The minimum amount of `tokenOut` that should be received.
    function _validateDCAOrder(DCAOrderLib.DCAOrder memory dcaOrder) internal view returns (uint256 amountIn, uint256 minAmountOut) {
        ICreditManagerV3 manager = ICreditManagerV3(dcaOrder.manager);

        // Ensure the DCA order has not been cancelled.
        if (dcaOrder.account == address(0)) {
            revert OrderIsCancelled();
        }

        // Ensure there are executions left.
        if (dcaOrder.executionsLeft == 0) {
            revert NoExecutionsLeft();
        }

        // Ensure the time interval has passed for the next execution.
        if (block.timestamp < dcaOrder.nextExecutionTime) {
            revert NotTimeYet();
        }

        // Ensure the borrower is still the owner of the credit account.
        if (manager.getBorrowerOrRevert(dcaOrder.account) != dcaOrder.borrower) {
            revert InvalidOrder();
        }

        // Check the balance of `tokenIn` in the borrower's credit account.
        uint256 balanceIn = IERC20(dcaOrder.tokenIn).balanceOf(dcaOrder.account);
        if (balanceIn <= 1) {
            revert NothingToSell();
        }

        // Get the current price of the `tokenIn` to `tokenOut` pair from the price oracle.
        uint256 ONE = 10 ** IERC20Metadata(dcaOrder.tokenIn).decimals();
        uint256 price = IPriceOracleV3(manager.priceOracle()).convert(ONE, dcaOrder.tokenIn, dcaOrder.tokenOut);
        // Calculate how much `tokenIn` can be sold and the minimum amount of `tokenOut` to receive.
        amountIn = dcaOrder.amountPerInterval > balanceIn ? balanceIn - 1 : dcaOrder.amountPerInterval;
        minAmountOut = amountIn * price / ONE;
    }
}
