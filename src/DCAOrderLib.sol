// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library DCAOrderLib {
    struct DCAOrder {
        address borrower;           // Address of the user who submitted the DCA order
        address manager;            // Address of the Gearbox credit manager
        address account;            // Address of the borrower's Gearbox credit account
        address tokenIn;            // Token being sold/exchanged
        address tokenOut;           // Token being bought
        uint256 amountPerInterval;  // Amount of `tokenIn` exchanged in each DCA execution
        uint256 interval;           // Time interval between each DCA execution (in seconds)
        uint256 nextExecutionTime;  // Timestamp when the next DCA execution can happen
        uint256 totalExecutions;    // Total number of executions for the DCA order
        uint256 executionsLeft;     // Number of executions left
    }
}
