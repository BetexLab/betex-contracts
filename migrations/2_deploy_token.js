const BetexToken = artifacts.require("./BetexToken.sol");

module.exports = function(deployer) {
    deployer.deploy(BetexToken, { gas: 1900000 });
};
