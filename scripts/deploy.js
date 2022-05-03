const { ethers } = require('hardhat');
const hre = require('hardhat');

async function main() {
  await hre.run('compile');
  const chainId = hre.network.config.chainId;

  const config = require('./config.json').chainId[chainId.toString()];
  const { subscriptionId, priceFeedAddress, vrfCoordinator, keyHash } = config;
  const Lottery = await ethers.getContractFactory('Lottery');
  const lottery = await Lottery.deploy(
    subscriptionId, priceFeedAddress, vrfCoordinator, keyHash);
  await lottery.deployed();
  console.log('Lottery deployed:', lottery.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
