## Gearbox Dollar Cost Averaging (DCA) bot

Creating and handling trades specialized for Dollar Cost Averaging(DCA) strategy.

Based on a template contract code 
* [Limit orders](https://dev.gearbox.fi/bots/limit-orders);

### Installation

Regular command `forge install` might not work in some cases. So we recommend to install all of the libraries separatly. You can find more information in the following link
[Proper installation](https://ethereum.stackexchange.com/questions/165955/forge-install-is-not-installing-the-dependencies/165958?noredirect=1#comment180305_165958) 

Next, create a `.env` file, copy the contents from `.env.example` and change placeholder values to the appropriate ones.

Finally, run `forge test` to ensure everything works.

### Deployment

You can deploy the bot using `forge script ./scripts/DCAOrderBot.s.sol --rpc-url <RPC_URL> `.

