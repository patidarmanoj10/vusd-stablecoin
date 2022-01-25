import {HardhatRuntimeEnvironment} from "hardhat/types";
import {DeployFunction} from "hardhat-deploy/types";

const name = "Treasury";
const vusd = "VUSD";
let version;

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();
  const vusdDeployment = await deployments.get(vusd);

  const deployed = await deploy(name, {
    from: deployer,
    args: [vusdDeployment.address],
    log: true,
  });

  const treasury = await hre.ethers.getContractAt(name, deployed.address);

  version = await treasury.VERSION();
};

export default func;
func.id = `${name}-${version}`;
func.tags = [name];
