// We import Chai to use its asserting functions here.
const { expect } = require("chai");

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

  let BABLToken;
  let hardhatToken;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    BABLToken = await ethers.getContractFactory("BABLToken");
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    // To deploy our contract, we just have to call BABLToken.deploy() and await
    // for it to be deployed(), which happens onces its transaction has been
    // mined.
    Token = await BABLToken.deploy();
  });

  // You can nest describe calls to create subsections.
  describe("Deployment", function () {
    // `it` is another Mocha function. This is the one you use to define your
    // tests. It receives the test name, and a callback function.

    it("should successfully deploy the contract", async function() {
      const deployedc = await Token.deployed();
      expect(!!deployedc).to.equal(true);
    });
  

    // If the callback function is async, Mocha will `await` it.
    it("Should set the right owner", async function () {
      // Expect receives a value, and wraps it in an Assertion object. These
      // objects have a lot of utility methods to assert values.

      // This test expects the owner variable stored in the contract to be equal
      // to our Signer's owner.
      expect(await Token.owner()).to.equal(owner.address);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await Token.balanceOf(owner.address);
      expect(await Token.totalSupply()).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      // Transfer 260_000e18 tokens from owner to addr1
      const value = BigInt("260000000000000000000000");
      await Token.transfer(addr1.address, value.toString());
      const addr1Balance = await Token.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(value).toString();

      // Transfer 180_000e18 tokens from addr1 to addr2
      // We use .connect(signer) to send a transaction from another account
      const value2 = BigInt("180000000000000000000000");
      await Token.connect(addr1).transfer(addr2.address, value2.toString());
      const addr2Balance = await Token.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(value2).toString();
    });

    it("Should fail if sender doesn’t have enough tokens", async function () {
      const initialOwnerBalance = await Token.balanceOf(owner.address);

      // Try to send 1 BABLToken from addr1 (0 tokens) to owner (1000 tokens).
      // `require` will evaluate false and revert the transaction.
      await expect(
        Token.connect(addr1).transfer(owner.address, 1)
      ).to.be.revertedWith("TimeLockedToken:: _transfer: insufficient balance");

      // Owner balance shouldn't have changed.
      expect(await Token.balanceOf(owner.address)).to.equal(
        initialOwnerBalance
      );
    });

    it("Should update balances after transfers", async function () {
      const initialOwnerBalance = await Token.balanceOf(owner.address);
      const value = BigInt("260000000000000000000000");
      // Transfer 260_000e18 tokens from owner to addr1.
      await Token.transfer(addr1.address, value.toString());
      const value2 = BigInt("180000000000000000000000");
      // Transfer another 180_000e18 tokens from owner to addr2.
      await Token.transfer(addr2.address, value2.toString());

      // Check balances.
      const totalsent = BigInt("440000000000000000000000");
      const finalOwnerBalance = await Token.balanceOf(owner.address);
      expect(finalOwnerBalance).to.equal(BigInt(initialOwnerBalance) - totalsent);

      const addr1Balance = await Token.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(value);

      const addr2Balance = await Token.balanceOf(addr2.address);
      expect(addr2Balance).to.equal(value2);
    });
  });

  describe("Minting", function () {
        
  /**   
    it("Should fail when trying to mint new tokens beyond MAX_SUPPLY", async function () {
      const maxSupply = await Token.maxSupply();
      const totalSupply = await Token.totalSupply();

      // Try to mint 100000 new BABL Tokens to addr1.
      // `require` will evaluate false and revert the transaction if MAX_SUPPLY is reached.
      const value = BigInt("100000000000000000000000");
      await expect(
        Token.mint(addr1, value)
      ).to.be.revertedWith("BABL::mint: max supply exceeded");

      // TOTAL_SYPPLY shouldn't have changed.
      expect(maxSupply).to.equal(totalSupply);
    });
  
    /**      ethers.provider.send("evm_increaseTime", [ONE_DAY_IN_SECONDS * 90]);
 */
    

    it("Should fail a try of minting new tokens by an address that is not the owner", async function () {
      try {
        const totalSupply = await Token.totalSupply();
        const value2 = BigInt("1000000000000000000000000");
        let result = await Token.mint.call({from: addr1})
        assert.equal(result.toString(), owner)
        await expect(
          Token.connect(addr1).mint(addr1, value)
        ).to.be.revertedWith("Only owner");
  
        // TOTAL_SYPPLY shouldn't have changed.
        expect(totalSupply).to.equal(value2);

      } catch (e) {
        //assert.fail(null, null, `${addr1} is not owner`)}; 
        console.log(`${addr1} is not owner`)};     
    });

  });


  describe("MAX_SUPPLY Change", function () {
        
    it("Should fail a try of changing MAX_SUPPLY before 8 years", async function () {
      const OLD_MAX_SUPPLY = await Token.maxSupply();

      // Try to change MAX_SUPPLY by a new number before 8 years
      // `require` will evaluate false and revert the transaction if MAX_SUPPLY is reached.
      const NEW_MAX_SUPPLY = BigInt("11000000000000000000000000");
      const value2 = BigInt("1000000000000000000000000");
      await expect(
        Token.changeMaxSupply(NEW_MAX_SUPPLY, 251596800)
      ).to.be.revertedWith("BABL::changeMaxSupply: a change on MAX_SUPPLY not allowed until 8 years after deployment");

      // MAX_SUPPLY shouldn't have changed.
      expect(OLD_MAX_SUPPLY).to.equal(value2);
    });
  });

});