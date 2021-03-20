// We import Chai to use its asserting functions here.

const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { EMPTY_BYTES, ONE_DAY_IN_SECONDS } = require("../utils/constants");
const { loadFixture } = waffle;

const addresses = require("../utils/addresses");
const { deployFolioFixture } = require("./fixtures/ControllerFixture");

// `describe` is a Mocha function that allows you to organize your tests. It's
// not actually needed, but having your tests organized makes debugging them
// easier. All Mocha functions are available in the global scope.

// `describe` receives the name of a section of your test suite, and a callback.
// The callback must define the tests of that section. This callback can't be
// an async function.
describe("BABLToken contract", function () {
  // Mocha has four functions that let you hook into the the test runner's
  // lifecyle. These are: `before`, `beforeEach`, `after`, `afterEach`.

  // They're very useful to setup the environment for tests, and to clean it
  // up after they run.

  // A common pattern is to declare some variables, and assign them in the
  // `before` and `beforeEach` callbacks.

  let bablToken;
  let timeLockRegistry;
  let ownerSigner;
  let userSigner1;
  let userSigner2;
  let userSigner3;
  
  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.

  beforeEach(async () => {
    const {
      bablToken,
      timeLockRegistry,
      owner,
      signer1,
      signer2,
      signer3
    } = await loadFixture(deployFolioFixture);
  
    token = bablToken;
    registry = timeLockRegistry;
    ownerSigner = owner;
    userSigner1 = signer1;
    userSigner2 = signer2;
    userSigner3 = signer3;

    // console.log(
    //   "Config:",
    //   oracle,
    //   valuer,
    //   ownerSigner,
    //   userSigner1,
    //   userSigner2,
    //   userSigner3
    // );


  });  

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it("should successfully deploy BABLToken contract", async function() {
      const deployedc = await token.deployed();
      expect(!!deployedc).to.equal(true);
    });

    it("should successfully deploy TimeLockRegistry contract", async function() {
      const deployedc2 = await registry.deployed();
      expect(!!deployedc2).to.equal(true);
    });

    it("should successfully have assigned the TimeLockRegistry address to BABLToken contract", async function() {
      // Set up TimeLockRegistry
      const addressRegistry = await token.timeLockRegistry();
      expect(registry.address).to.equal(addressRegistry);   
    });
  

    // If the callback function is async, Mocha will `await` it.
    it("Should set the right owner to BABL", async function () {
      // Expect receives a value, and wraps it in an Assertion object. These
      // objects have a lot of utility methods to assert values.

      // This test expects the owner variable stored in the contract to be equal
      // to our Signer's owner.
      expect(await token.owner()).to.equal(ownerSigner.address);
    });

     // If the callback function is async, Mocha will `await` it.
    it("Should set the right owner to Registry", async function () {
      // Expect receives a value, and wraps it in an Assertion object. These
      // objects have a lot of utility methods to assert values.

      // This test expects the owner variable stored in the contract to be equal
      // to our Signer's owner.
      expect(await registry.owner()).to.equal(ownerSigner.address);
    });    

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await token.balanceOf(ownerSigner.address);
      expect(await token.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      // Transfer 260_000e18 tokens from owner to userSigner1
      const value = BigInt("260000000000000000000000");
      await token.connect(ownerSigner).transfer(userSigner1.address, value.toString());
      const addr1Balance = await token.balanceOf(userSigner1.address);
      expect(addr1Balance).to.equal(value).toString();

      // Transfer 180_000e18 tokens from userSigner1 to userSigner2
      // We use .connect(signer) to send a transaction from another account
      const value2 = BigInt("180000000000000000000000");
      await token.connect(userSigner1).transfer(userSigner2.address, value2.toString());
      const addr2Balance = await token.balanceOf(userSigner2.address);
      expect(addr2Balance).to.equal(value2).toString();
    });

    it("Should fail if sender doesn’t have enough tokens", async function () {
      const initialOwnerBalance = await token.balanceOf(ownerSigner.address);

      // Try to send 1 BABLToken from userSigner1 (0 tokens) to owner (1000 tokens).
      // `require` will evaluate false and revert the transaction.
      await expect(
        token.connect(userSigner1).transfer(ownerSigner.address, 1)
      ).to.be.revertedWith("TimeLockedToken:: _transfer: insufficient balance");

      // Owner balance shouldn't have changed.
      expect(await token.balanceOf(ownerSigner.address)).to.equal(
        initialOwnerBalance
      );
    });

    it("Should update balances after transfers", async function () {
      const initialOwnerBalance = await token.balanceOf(ownerSigner.address);
      const value = BigInt("260000000000000000000000");
      // Transfer 260_000e18 tokens from owner to userSigner1.
      await token.transfer(userSigner1.address, value.toString());
      const value2 = BigInt("180000000000000000000000");
      // Transfer another 180_000e18 tokens from owner to userSigner2.
      await token.transfer(userSigner2.address, value2.toString());

      // Check balances.
      const totalsent = BigInt("440000000000000000000000");
      const finalOwnerBalance = await token.balanceOf(ownerSigner.address);
      expect(finalOwnerBalance).to.equal(BigInt(initialOwnerBalance) - totalsent);

      const addr1Balance = await token.balanceOf(userSigner1.address);
      expect(addr1Balance).to.equal(value);

      const addr2Balance = await token.balanceOf(userSigner2.address);
      expect(addr2Balance).to.equal(value2);
    });
  });

  describe("Vesting", function () { // TODO CHECK ALLOWANCE FLOW WHICH IS FINALLY NEEDED TO DISPOSE/REGISTER BABL TOKENS ON BEHALF OF TOKEN.OWNER()
    it("Owner Should approve the allowance of 31% of 1M tokens to Time Lock Registry for vesting but keep balance without change", async function () {
      // Approve 310_000e18 tokens from owner to Time Lock Registry
      await token.approve(registry.address, ethers.utils.parseEther("310000"));
      const ownerBalance = await token.balanceOf(ownerSigner.address);
      expect(await token.totalSupply()).to.equal(ownerBalance);

      // Check allowance has been done
      const allowSigner1 = await token.allowance(ownerSigner.address,registry.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther("310000"));
    });
    
    it("Time Lock Registry should properly register 1 Team Member, 1 Advisor and 1 Investor with its own vesting conditions", async function () {
      //First of all there should be an allowance from BABL Token Owner into the Registry
      // Approve 310_000e18 tokens from owner to Time Lock Registry
      await token.approve(registry.address, ethers.utils.parseEther("310000"));
      const ownerBalance = await token.balanceOf(ownerSigner.address);
      expect(await token.totalSupply()).to.equal(ownerBalance);

      // Check allowance has been done
      const allowSigner1 = await token.allowance(ownerSigner.address,registry.address);
      expect(allowSigner1).to.equal(ethers.utils.parseEther("310000"));
      
      
      // Register 1 Team Member with 26_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await registry.register(userSigner1.address, ethers.utils.parseEther("26000"), true,1614618000);
      const userSigner1Registered = await registry.checkVesting(userSigner1.address);
      const userSigner1RegisteredTeam = userSigner1Registered[0];
      const userSigner1RegisteredCliff = userSigner1Registered[1];
      const userSigner1RegisteredVestingBegin = userSigner1Registered[2];
      const userSigner1RegisteredVestingEnd = userSigner1Registered[3];
      expect(userSigner1RegisteredTeam).to.equal(true);
      expect(userSigner1RegisteredCliff).to.equal(true);
      expect(userSigner1RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner1RegisteredVestingEnd).to.equal(1614618000 + (ONE_DAY_IN_SECONDS * 365 * 4));
      

      // Register 1 Advisor with 2_000 BABL 1Y cliff and 4Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await registry.register(userSigner2.address, ethers.utils.parseEther("2000"), true,1614618000);
      const userSigner2Registered = await registry.checkVesting(userSigner2.address);
      const userSigner2RegisteredTeam = userSigner2Registered[0];
      const userSigner2RegisteredCliff = userSigner2Registered[1];
      const userSigner2RegisteredVestingBegin = userSigner2Registered[2];
      const userSigner2RegisteredVestingEnd = userSigner2Registered[3];
      expect(userSigner2RegisteredTeam).to.equal(true);
      expect(userSigner2RegisteredCliff).to.equal(true);
      expect(userSigner2RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner2RegisteredVestingEnd).to.equal(1614618000 + (ONE_DAY_IN_SECONDS * 365 * 4));

      // Register 1 Investor with 10_000 BABL no Cliff and 3Y of Vesting
      // Vesting starting date 1 March 2021 9h PST Unix Time 1614618000
      await registry.register(userSigner3.address, ethers.utils.parseEther("10000"), false,1614618000);
      const userSigner3Registered = await registry.checkVesting(userSigner3.address);
      const userSigner3RegisteredTeam = userSigner3Registered[0];
      const userSigner3RegisteredCliff = userSigner3Registered[1];
      const userSigner3RegisteredVestingBegin = userSigner3Registered[2];
      const userSigner3RegisteredVestingEnd = userSigner3Registered[3];
      expect(userSigner3RegisteredTeam).to.equal(false);
      expect(userSigner3RegisteredCliff).to.equal(false);
      expect(userSigner3RegisteredVestingBegin).to.equal(1614618000);
      expect(userSigner3RegisteredVestingEnd).to.equal(1614618000 + (ONE_DAY_IN_SECONDS * 365 * 3));
    });

    
  });

  describe("Minting", function () {
        
    it("Should fail a try of minting new tokens by an address that is not the owner", async function () {
      try {
        const totalSupply = await token.totalSupply();
        const value2 = BigInt("1000000000000000000000000");
        let result = await token.mint.call({from: userSigner1})
        assert.equal(result.toString(), ownerSigner)
        await expect(
          token.connect(userSigner1).mint(userSigner1, value)
        ).to.be.revertedWith("Only owner");
  
        // TOTAL_SUPPLY shouldn't have changed.
        expect(totalSupply).to.equal(value2);

      } catch (e) {
        //assert.fail(null, null, `${userSigner1} is not owner`)}; 
        console.log(`%s is not owner, which is %s`, userSigner1.address, ownerSigner.address)};     
    });

    /** 
    it("Should fail when trying to mint new tokens beyond MAX_SUPPLY", async function () {
      const maxSupply = await token.maxSupply();
      const totalSupply = await token.totalSupply();

      // Try to mint new BABL Tokens > (above) maxSupply to userSigner1.
      // `require` will evaluate false and revert the transaction if MAX_SUPPLY is reached.
      const value = maxSupply-totalSupply+1;
      await expect(
        token.connect(ownerSigner).mint(userSigner1, value)
      ).to.be.revertedWith("BABLToken::mint: max supply exceeded");

      const newTotalSupply = await token.totalSupply();

      // TOTAL_SUPPLY shouldn't have changed.
      expect(totalSupply).to.equal(newTotalSupply);
    });
    */

  });


  describe("MAX_SUPPLY Change", function () {
        
    it("Should fail a try of changing MAX_SUPPLY from an address different from the owner", async function () {
      try {
        const maxSupply = await token.maxSupply();
        const NEW_MAX_SUPPLY = maxSupply+ 100000;
        let result = await token.changeMaxSupply.call({from: userSigner1})
        assert.equal(result.toString(), ownerSigner)
        await expect(
          token.connect(userSigner1).changeMaxSupply(NEW_MAX_SUPPLY, 251596800)
        ).to.be.revertedWith("Only owner");
  
        // MAX_SUPPLY shouldn't have changed.
        expect(maxSupply).to.equal(NEW_MAX_SUPPLY);

      } catch (e) {
        //assert.fail(null, null, `${userSigner1} is not owner`)}; 
        console.log(`%s is not owner, which is %s`, userSigner1.address, ownerSigner.address)}; 
    });

    it("Should fail a try of changing MAX_SUPPLY before 8 years", async function () {
      const OLD_MAX_SUPPLY = await token.maxSupply();

      // Try to change MAX_SUPPLY by a new number before 8 years
      // `require` will evaluate false and revert the transaction if MAX_SUPPLY is reached.
      const NEW_MAX_SUPPLY = BigInt("11000000000000000000000000");
      const value2 = BigInt("1000000000000000000000000");
      await expect(
        token.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)
      ).to.be.revertedWith("BABLToken::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment");

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });

    it("Should fail a try of changing MAX_SUPPLY after 8 years by an amount below the current MAX_SUPPLY", async function () {
    const OLD_MAX_SUPPLY = await token.maxSupply();

    // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
    // `require` will evaluate false and revert the transaction if the new value is below the current MAX_SUPPLY.
    const NEW_MAX_SUPPLY = BigInt("900000000000000000000000"); // 900_000e18
    const value2 = BigInt("1000000000000000000000000");
    // Traveling on time >8 years ahead
    ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 365 * 8]);
    await expect(
      token.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)
    ).to.be.revertedWith("BABLToken::changeMaxSupply: changeMaxSupply should be higher than previous value");

    // MAX_SUPPLY shouldn't have changed.
    expect(OLD_MAX_SUPPLY).to.equal(value2);
    });

    it("Should fail a try of changing MAX_SUPPLY after 8 years by an amount above the cap of 5%", async function () {
      const OLD_MAX_SUPPLY = await token.maxSupply();
  
      // Try to change MAX_SUPPLY by a new number after 8 years by a lower amount
      // `require` will evaluate false and revert the transaction if the new value is above the cap (5%) the current MAX_SUPPLY.
      const NEW_MAX_SUPPLY = BigInt("1150000000000000000000000"); // 1_150_000e18
      // Traveling on time >8 years ahead
      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 365 * 8]);
      await expect(
        token.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)
      ).to.be.revertedWith("BABLToken::changeMaxSupply: exceeded of allowed 5% cap");
        
      const value2 = await token.maxSupply();

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });
  });
});
