const TokenVesting = artifacts.require("TokenVesting");

module.exports = function (deployer) {
  deployer.deploy(TokenVesting, "10000000000000000000000000", "1658480246148");
};
