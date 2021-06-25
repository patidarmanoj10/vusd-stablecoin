import {HardhatRuntimeEnvironment} from "hardhat/types";
import {DeployFunction} from "hardhat-deploy/types";
import {ethers} from "hardhat";

const CURVE_FACTORY = "0x0959158b6040D32d04c301A72CBFD6b39E21c9AE";
const THREEPOOL = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7";
const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

const VUSD = "VUSD";
const name = "CurveMetapool";
const version = "v1.0.0";

// Curve metapool parameters
const A = ethers.BigNumber.from("150");
const FEE = ethers.BigNumber.from("4000000");

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {save} = deployments;
  const {deployer} = await getNamedAccounts();

  const deployedVUSD = "0x677ddbd918637E5F2c79e164D402454dE7dA8619";

  const CurveFactory = await ethers.getContractAt("ICurveFactory", CURVE_FACTORY);

  let deployTx = await CurveFactory.deploy_metapool(THREEPOOL, VUSD, VUSD, deployedVUSD, A, FEE);

  let deployTxInfo = await deployTx.wait();
  let events = deployTxInfo.events.filter((eventInfo) => eventInfo.event == "MetaPoolDeployed");

  if (!events.length) throw "Metapool deployment failed";

  // finds address of deployed metapool
  // can't get it from the event emitted, we use that just to make sure pool has been deployed
  const CurveMetapoolAddress = await CurveFactory.find_pool_for_coins(deployedVUSD, USDC);

  const CurveMetapool = await ethers.getContractAt("ICurveMetapool", CurveMetapoolAddress);
  const deployedBytecode = await ethers.provider.getCode(CurveMetapoolAddress);
  const abi = CurveMetapool.interface.format(ethers.utils.FormatTypes.full) as any[];

  // low-level save of deployed metapool address and tx data used to create the metapool
  save(name, {
    abi: abi,
    address: CurveMetapoolAddress,
    receipt: deployTxInfo,
    transactionHash: deployTx.hash,
    execute: {
      methodName: "deploy_metapool",
      args: [THREEPOOL, VUSD, VUSD, deployedVUSD, A, FEE],
    },
    deployedBytecode,
  });
};
export default func;
func.id = `${name}-${version}`;
func.tags = [name];