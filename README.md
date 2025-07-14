# VUSD

A stablecoin pegged to the US Dollar, backed by interest-generating collateral.

## Setup

1. Install 

   ```sh
   git clone https://github.com/vesperfi/vusd-stablecoin.git
   cd vusd-stablecoin
   npm install
   ```
2. Install Foundry
   - follow instruction from official foundry doc [here](https://getfoundry.sh/introduction/installation).

## Test
1. Setup `FORK_NODE_URL` and `FORK_BLOCK_NUMBER` in env.
    ```sh
    # Export variables to env via CLI
    export FORK_NODE_URL=<eth mainnet url>
    export FORK_BLOCK_NUMBER=<eth mainnet block number>
    
    # Another option is to use ".env" file

    touch .env
    # Edit .env file and add env vars
    FORK_NODE_URL=<eth mainnet url>
    FORK_BLOCK_NUMBER=<eth mainnet block number>
    ```
2. Run `forge test` to run unit tests.

## Deployment and configuration info

- `NODE_URL` is required for deployment. Set it in env.

- VUSD is already deployed on chain at `0x677ddbd918637E5F2c79e164D402454dE7dA8619` and we are not releasing new version.
- Any new release will deploy either Minter, Redeemer and/or Treasury.
  
* Below are the configuration steps for new release of Minter, Redeemer and Treasury
  >  Below operations will be done via VUSD governor.
  1. call `updateMinter(_newMinter)` on VUSD
  2. call `updateTreasury(_newTreasury)` on VUSD
  3. call `updateRedeemer(_newRedeemer)` on **New** Treasury
  4. call `addKeeper(_keeperAddress)` on **New** Treasury
  5. call `migrate(_newTreasury)` on **Old** Treasury

    <br>

    > PS: Step 5 has dependency on step 2, rest can be done in any order.

- Current keeper of VUSD system `0x76d266DFD3754f090488ae12F6Bd115cD7E77eBD`. It can be added in new treasury in step 4.

### Deployment
> Set `NODE_URL` in env, if not already.
- Minter
  ```bash
  npm run deploy -- --tags Minter --gasprice <gas price> --network mainnet
  ```

- Redeemer
  ```bash
  npm run deploy -- --tags Redeemer --gasprice <gas price> --network mainnet
  ```

- Treasury
  ```bash
  npm run deploy -- --tags Treasury --gasprice <gas price> --network mainnet
  ```