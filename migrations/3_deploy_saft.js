const timestamp = require("unix-timestamp");
const BetexSAFT = artifacts.require("./BetexSAFT.sol");

module.exports = function(deployer) {
    deployer.deploy(
        BetexSAFT,
        timestamp.fromDate('2018-02-20'),
        { gas: 4200000 }
    );
};
