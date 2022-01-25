# VUSD

A stablecoin pegged to the US Dollar, backed by interest-generating collateral.

## Setup

1. Install 

   ```sh
   git clone https://github.com/vesperfi/vusd-stablecoin.git
   cd vusd-stablecoin
   npm install
   ```
2. set NODE_URL in env
    ```sh
    export NODE_URL=<eth mainnet url>
    ```
    Or
    Use .env file
    ```sh
    touch .env
    # Edit .env file and add NODE_URL
    NODE_URL=<eth mainnet url>
    ```

3. Test
> These tests will run on mainnet fork, which already configured no extra steps needed.

   ```sh
   npm test
   ```

4. Run test with coverage

```sh
npm run coverage
```

## Mainnet deployment and configuration info

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

### Deployment commands
- Minter
  ```bash
  npm run deploy -- --tags Minter --gasprice 110000000000 --network mainnet
  ```

- Redeemer
  ```bash
  npm run deploy -- --tags Redeemer --gasprice 110000000000 --network mainnet
  ```

- Treasury
  ```bash
  npm run deploy -- --tags Treasury --gasprice 110000000000 --network mainnet
  ```