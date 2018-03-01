const timestamp = require("unix-timestamp");
const BetexSAFT = artifacts.require("./BetexSAFT.sol");

module.exports = function(deployer, network, accounts) {
    const addressBetex = "0xb7b9bbc420761d5cb2620731adaa2eb97c970290";
    const addressAdmin = "0xa5F15E35a9546D37d8bCBc1370F0B5033F91F740";

    let wallet;
    let betexSaft;

    if (network === "mainnet")
        wallet = addressBetex;
    else
        wallet = accounts[0];

    deployer.deploy(
        BetexSAFT,
        timestamp.fromDate('2018-03-01'),
        timestamp.fromDate('2018-03-31 23:59:59'),
        wallet,
        { gas: 4600000 }
    ).then(() => {
        return BetexSAFT.deployed();
    }).then(_betexSaft => {
        betexSaft = _betexSaft;
    }).then(() => {
        return betexSaft.addCollector('0x455448', 18, "json(https://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd");
    }).then(() => {
        return betexSaft.addCollector('0x425443', 8, "json(https://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd");
    }); 
};
