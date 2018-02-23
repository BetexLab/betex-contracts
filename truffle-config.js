const HDWalletProvider = require('truffle-hdwallet-provider');
const fs = require('fs');

let secrets;

if (fs.existsSync('secrets.json')) {
    secrets = JSON.parse(fs.readFileSync('secrets.json', 'utf8'));
} else {
    throw new Error('No secrets.json found!');
}

console.log(`Using mnemonic '${secrets.mnemonic}'.`);
console.log(`Using infura api key '${secrets.infuraApiKey}'.`);

module.exports = {
    networks: {
        development: {
            host: 'localhost',
            port: 8545,
            network_id: '*' // Match any network id
        },
        ropsten: {
            provider: new HDWalletProvider(secrets.mnemonic, 'https://ropsten.infura.io/' + secrets.infuraApiKey),
            network_id: 3,
            gas: 250000,
            gasPrice: 20000000000 // 20 Gwei
        },
        mainnet: {
            provider: new HDWalletProvider(secrets.mnemonic, 'https://mainnet.infura.io/' + secrets.infuraApiKey),
            network_id: 1,
            gas: 250000,
            gasPrice: 10000000000 // 20 Gwei
        }
    },
    secrets: secrets
};
