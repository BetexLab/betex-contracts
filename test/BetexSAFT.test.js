const BetexSAFT = artifacts.require('BetexSAFT');

const assertRevert = require('./helpers/assertRevert');
const expectThrow = require('./helpers/expectThrow');
const increaseTimeTo = require('./helpers/increaseTime');
const latestTime = require('./helpers/latestTime');
const ether = require('./helpers/ether');


contract('BetexSAFT', ([owner, wallet, admin, betex, funder, nonAutorizedFunder]) => {

  this.startTime = 1519862400; //03/01/2018;
  this.endTime = 1522454400; // 03/31/2018;
 
  const RATE_EXPONENT = 4;
  const TOKEN_PRICE = 3;

  before(async () => {
    if(latestTime() < this.startTime) {
      await increaseTimeTo(this.startTime);
    }
  });
  
  beforeEach(async () => {
    this.saft = await BetexSAFT.new(this.startTime, this.endTime, wallet);

    await this.saft.addCollector('0x455448', 18, "json(https://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd");
    await this.saft.addCollector('0x425443', 8, "json(https://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd");

    await this.saft.addRefiller(admin);
    await this.saft.addRefiller(betex);

    await this.saft.sendTransaction({from: owner, value: ether(0.1)});
    await this.saft.setOraclizeGasPrice(100000);
  });

  it('should be able to create contract with correct parameters', async() => {
    const startTime = await this.saft.startTime.call();
    const endTime = await this.saft.endTime.call();
    const fundsWallet = await this.saft.wallet.call();
    assert.equal(startTime, this.startTime);
    assert.equal(endTime, this.endTime);
    assert.equal(fundsWallet, wallet);
  });

  it('should be able to add initial collectors', async () => {
    const collectorsCount = await this.saft.collectorsCount.call();
    const ethCollector = await this.saft.collectors.call(0);
    const btcCollector = await this.saft.collectors.call(1);

    assert.equal(collectorsCount, 2);

    assert.equal(ethCollector[0], '0x455448');
    assert.equal(ethCollector[1], 18);
    assert.equal(ethCollector[2], "json(https://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd");

    assert.equal(btcCollector[0], '0x425443');
    assert.equal(btcCollector[1], 8);
    assert.equal(btcCollector[2], "json(https://api.coinmarketcap.com/v1/ticker/bitcoin/).0.price_usd");
  });

  it('should be able to add initial refillers', async () => {
    const isAdminRefiller = await this.saft.refillers.call(admin);
    const isBetexRefiller = await this.saft.refillers.call(betex);

    assert.equal(isAdminRefiller, true);
    assert.equal(isBetexRefiller, true);
  });

  it('should be able to add a direct funding map', async () => {
    const funderId = 123456;
    
    await this.saft.addDirect(funder, funderId);

    const directFunderId = await this.saft.direct.call(funder);

    assert.equal(funderId, directFunderId);
  });

  it('should be able to add funder to KYC failed list', async () => {
    const funderId = 123456;
    const failedKycCountBefore = await this.saft.failedKycCount.call();
    await this.saft.failedKyc(funderId);
    const failedKycCountAfter = await this.saft.failedKycCount.call();

    const isKycFailed = await this.saft.isKycFailed.call(funderId);

    assert.equal(failedKycCountBefore.toNumber() + 1 , failedKycCountAfter.toNumber());
    assert.equal(isKycFailed, true);
  });

  it('should not accept ether from non autorized funder', async () => {
    await assertRevert(this.saft.sendTransaction({from: nonAutorizedFunder, value: ether(1)}));
  });

  it('should not accept payment < 0.5 ETH', async () => {
    const funderId = 1234;
    await this.saft.addDirect(funder, funderId);
    await assertRevert(this.saft.sendTransaction({from: funder, value: ether(0.498)}));
  });
  
  it('should accept ether to contract for direct funding', async () => {
    const funderId = 1235;
    const funds = ether(1);
    await this.saft.addDirect(funder, funderId);
    const funderRealId = await this.saft.direct.call(funder);
    const result = await this.saft.sendTransaction({from: funder, value: funds});
  
    let resFunderId, orderId;
    for (var i = 0; i < result.logs.length; i++) {
      var log = result.logs[i];
      if (log.event == "OrderEvent") {
        resFunderId = log.args.funderId;
        orderId = log.args.orderId;
        break;
      }
    }

    const order = await this.saft.orders.call(orderId);
    assert.equal(order[0].toNumber(), funderId); //funder id match
    assert.equal(order[1], 0); //collector - ETH (index 0)
    assert.equal(order[2].toNumber(), funds.toNumber()); //paid funds match

    await setTimeout( async() => {
      const order = await this.saft.orders.call(orderId);
      const tokensRequested = new web3.BigNumber(order[3]).mul(funds).div(10 ** RATE_EXPONENT).div(TOKEN_PRICE);
     
      const tokenPurchased = await this.saft.purchased.call(funderId);
      assert.equal(tokenPurchased.toNumber(), tokensRequested.toNumber());
    }, 30000 );
  });

  it('should make order in BTC', async () => {
    const funderId = 123;
    const funds = 1000000000;
    const tx = 1234;
    const result = await this.saft.order(funderId, 1, funds, tx);

    let resFunderId, orderId;
    for (var i = 0; i < result.logs.length; i++) {
      var log = result.logs[i];
      if (log.event == "OrderEvent") {
        resFunderId = log.args.funderId;
        orderId = log.args.orderId;
        break;
      }
    }

    const order = await this.saft.orders.call(orderId);
    assert.equal(order[0].toNumber(), funderId); //funder id match
    assert.equal(order[1].toNumber(), 1); //collector - BTC (index 1)
    assert.equal(order[2].toNumber(), funds); //paid funds match

    await setTimeout( async() => {
      const order = await this.saft.orders.call(orderId);
      const tokensRequested = new web3.BigNumber(order[3]).mul(funds).mul(10 ** 10).div(10 ** RATE_EXPONENT).div(TOKEN_PRICE);
      const tokenPurchased = await this.saft.purchased.call(funderId);
      assert.equal(tokenPurchased.toNumber(), tokensRequested.toNumber());
    }, 30000 );
  });

  it('should make order in ETH', async () => {
    const funderId = 12345;
    const funds = 1000000000;
    const tx = 12345;
    const result = await this.saft.order(funderId, 0, funds, tx);

    let resFunderId, orderId;
    for (var i = 0; i < result.logs.length; i++) {
      var log = result.logs[i];
      if (log.event == "OrderEvent") {
        resFunderId = log.args.funderId;
        orderId = log.args.orderId;
        break;
      }
    }

    const order = await this.saft.orders.call(orderId);
    assert.equal(order[0].toNumber(), funderId); //funder id match
    assert.equal(order[1].toNumber(), 0); //collector - ETH (index 0)
    assert.equal(order[2].toNumber(), funds); //paid funds match

    await setTimeout( async() => {
      const order = await this.saft.orders.call(orderId);
      
      const tokensRequested = new web3.BigNumber(order[3]).mul(funds).div(10 ** RATE_EXPONENT).div(TOKEN_PRICE);
      const tokenPurchased = await this.saft.purchased.call(funderId);
      assert.equal(tokenPurchased.toNumber(), tokensRequested.toNumber());
    }, 30000 );
  });

});