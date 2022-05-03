## Basic Lottery
Use VRF to generate random number which determines lottery winner. Prerequisite: create a [VRF subscription](https://vrf.chain.link/) and fund with LINK token. 
* A minimum entrance fee is imposed (USD denominated). The amount is converted to Ether (native token of the chain) using Chainlink price feed oracle.
* Admin manually controls when to start and end the lottery.
* After lottery ends, all deposit is sent to the winner.

```bash
npm install

# BSC Testnet deploy
hh run scripts/deploy.js --network bscTestnet

# BSC Testnet verify
hh verify --network bscTestnet \
  --constructor-args ./scripts/args/bscTestnet.js \
  0xa7d798621096f761342804272E0752B677E25783

# Rinkeby deploy
run scripts/deploy.js --network rinkeby

# Rinkeby verify
hh verify --network rinkeby \
  --constructor-args ./scripts/args/rinkeby.js \
  0x197B6aA305EE2868D39530F94505987debaa9055
```

## Basic Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, a sample script that deploys that contract, and an example of a task implementation, which simply lists the available accounts.

Try running some of the following tasks:

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
node scripts/sample-script.js
npx hardhat help
```

======

# Tasks

- The story:
    - Project needs initial contribution (seed phase)
        - Users can deposit pre-defined amount for certain benefits
            - Share of treasury/fees
            - Rupee allocation
    - Game Begins
        - Users deposit AVAX and enter every hour to "win"
            - Fee applied
            - Drawing costs 0.01 AVAX
            - Expedited draw for 0.1 AVAX but reduced loser's pool allocation
        - If win:
            - User can withdraw avax at the current value of their rupees
            - Fee applied at claim
            - 3x max payout
            - Percentage of the excess winnings sent to treasury and dev
        - If lose:
            - Incremented loss count up to 5
            - Once 5 consecutive losses are realized, a prize is available to claim from loser's pot
            - Calculated by percentage of investment up to a certain limit
                - As well as reduced by expedited draws to avoid abuse
            - Suggested calculation:
                - User's investment compared to full pool
                - Percentage applied against loser's pool
                - Pay out 20% of that value (up to limit)
            - Fee applied at claim?
    - Excess TVL use case
        - NFT collection which earns rewards (drains TVL overtime to avoid untouchable funds)

- Work on:
    - [x] Chainlink VRF
    - [] Loser's increment
      - [] And loser's pool
    - [] Seed phase of contract
    - [] lastDraw
        - this is set in the fulfillRandomness function
        - and is checked in the draw function
        - set var for drawCooldown (set for an hour?)

- Completed tasks:
    - Incorporate max winnings
        - This is actually not done, since you want to direct some of those excess earnings elsewhere