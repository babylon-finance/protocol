// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IBabController} from '../interfaces/IBabController.sol';
import {IYearnVaultRegistry} from '../interfaces/IYearnVaultRegistry.sol';

import {ControllerLib} from '../lib/ControllerLib.sol';

/**
 * @title YearnVaultRegistry
 * @author Babylon Finance Protocol
 *
 * Abstraction for all the different vaults
 */
contract YearnVaultRegistry is IYearnVaultRegistry {
    using ControllerLib for IBabController;

    /* ============ Constants ============ */

    IBabController public immutable controller;

    /* ============ State Variables ============ */

    // Mapping of valid Vaults
    mapping(address => bool) public override vaults;
    address[] public vaultList;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller is not valid');
        controller = _controller;
        // Yearn vaults
        // https://medium.com/yearn-state-of-the-vaults/the-vaults-at-yearn-9237905ffed3
        _addVault(0xc5bDdf9843308380375a611c18B50Fb9341f502A);
        _addVault(0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a);
        _addVault(0xdb25cA703181E7484a155DD612b06f57E12Be5F0);
        _addVault(0xF29AE508698bDeF169B89834F76704C3B205aedf);
        _addVault(0x873fB544277FD7b977B196a826459a69E27eA4ea);
        _addVault(0x671a912C10bba0CFA74Cfc2d6Fba9BA1ed9530B2);
        _addVault(0xa5cA62D95D24A4a350983D5B8ac4EB8638887396);
        _addVault(0xB8C3B7A2A618C552C23B1E4701109a9E756Bab67);
        _addVault(0xa258C4606Ca8206D8aA700cE2143D7db854D168c);
        _addVault(0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9);
        _addVault(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);
        _addVault(0xA696a63cc78DfFa1a63E9E50587C197387FF6C7E);
        _addVault(0x7Da96a3891Add058AdA2E826306D812C638D87a7);
        _addVault(0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42);
        _addVault(0xd9788f3931Ede4D5018184E198699dC6d66C1915);
        _addVault(0x4A3FE75762017DB0eD73a71C9A06db7768DB5e66);
        _addVault(0x6d765CbE5bC922694afE112C140b8878b9FB0390);
        _addVault(0xFD0877d9095789cAF24c98F7CCe092fa8E120775);
        // Curve yearn vaults
        _addVault(0xE537B5cc158EB71037D4125BDD7538421981E6AA); // Curve 3Crypto Pool yVault
        _addVault(0x6FAfCA7f49B4Fd9dC38117469cd31A1E5aec91F5); // Curve USDM Pool yVault
        _addVault(0x718AbE90777F5B778B52D553a5aBaa148DD0dc5D); // Curve alETH Pool yVault
        _addVault(0x8b9C0c24307344B6D7941ab654b2Aeee25347473); // Curve EURN Pool yVault
        _addVault(0xd8C620991b8E626C099eAaB29B1E3eEa279763bb); // Curve MIM-UST
        _addVault(0x0d4EA8536F9A13e4FBa16042a46c30f092b06aA5); // Curve EURT Pool yVault
        _addVault(0x2DfB14E32e2F8156ec15a2c21c3A6c053af52Be8); // Curve MIM Pool yVault
        _addVault(0x4560b99C904aAD03027B5178CCa81584744AC01f); // Curve cvxCRV Pool yVault
        _addVault(0x67e019bfbd5a67207755D04467D6A70c0B75bF60); // Curve ibEUR Pool yVault
        _addVault(0x528D50dC9a333f01544177a924893FA1F5b9F748); // Curve ibKRW Pool yVault
        _addVault(0x595a68a8c9D5C230001848B69b1947ee2A607164); // Curve ibGBP Pool yVault
        _addVault(0x1b905331F7dE2748F4D6a0678e1521E20347643F); // Curve ibAUD Pool yVault
        _addVault(0x490bD0886F221A5F79713D3E84404355A9293C50); // Curve ibCHF Pool yVault
        _addVault(0x59518884EeBFb03e90a18ADBAAAB770d4666471e); // Curve ibJPY Pool yVault
        _addVault(0x8cc94ccd0f3841a468184aCA3Cc478D2148E1757); // Curve mUSD Pool yVault
        _addVault(0x625b7DF2fa8aBe21B0A976736CDa4775523aeD1E); // Curve HBTC Pool yVault
        _addVault(0x3D27705c64213A5DcD9D26880c1BcFa72d5b6B0E); // Curve USDK Pool yVault
        _addVault(0x80bbeE2fa460dA291e796B9045e93d19eF948C6A); // Curve Pax Pool yVault
        _addVault(0xC116dF49c02c5fD147DE25Baa105322ebF26Bd97); // Curve RSV Pool yVault
        _addVault(0x28a5b95C101df3Ded0C0d9074DB80C438774B6a9); // Curve USDT Pool yVault
        _addVault(0x3D980E50508CFd41a13837A60149927a11c03731); // Curve triCrypto Pool yVault
        _addVault(0x25212Df29073FfFA7A67399AcEfC2dd75a831A1A); // Curve EURS Pool yVault
        _addVault(0x5a770DbD3Ee6bAF2802D29a901Ef11501C44797A); // Curve sUSD Pool yVault
        _addVault(0x39CAF13a104FF567f71fd2A4c68C026FDB6E740B); // Curve Aave Pool yVault
        _addVault(0x054AF22E1519b020516D72D749221c24756385C9); // Curve HUSD Pool yVault
        _addVault(0x3B96d491f067912D18563d56858Ba7d6EC67a6fa); // Curve USDN Pool yVault
        _addVault(0xBfedbcbe27171C418CDabC2477042554b1904857); // Curve rETH Pool yVault
        _addVault(0x132d8D2C76Db3812403431fAcB00F3453Fc42125); // Curve ankrETH Pool yVault
        _addVault(0xf2db9a7c0ACd427A680D640F02d90f6186E71725); // Curve LINK Pool yVault
        _addVault(0xA74d4B67b3368E83797a35382AFB776bAAE4F5C8); // Curve alUSD Pool yVault
        _addVault(0xC4dAf3b5e2A9e93861c3FBDd25f1e943B8D87417); // Curve USDP Pool yVault
        _addVault(0x1C6a9783F812b3Af3aBbf7de64c3cD7CC7D1af44); // Curve UST Pool yVault
        _addVault(0x30FCf7c6cDfC46eC237783D94Fc78553E79d4E9C); // Curve DUSD Pool yVault
        _addVault(0xf8768814b88281DE4F532a3beEfA5b85B69b9324); // Curve TUSD Pool yVault
        _addVault(0x4B5BfD52124784745c1071dcB244C6688d2533d3); // Curve Y Pool yVault
        _addVault(0x84E13785B5a27879921D6F685f041421C7F482dA); // Curve 3pool yVault
        _addVault(0x2a38B9B0201Ca39B17B460eD2f11e4929559071E); // Curve GUSD Pool yVault
        _addVault(0x27b7b1ad7288079A66d12350c828D3C00A6F07d7); // Curve Iron Bank Pool yVault
        _addVault(0x986b4AFF588a109c09B50A03f42E4110E29D353F); // Curve sETH Pool yVault
        _addVault(0xdCD90C7f6324cfa40d7169ef80b12031770B4325); // Curve stETH Pool yVault
        _addVault(0x8414Db07a7F743dEbaFb402070AB01a4E0d2E45e); // Curve sBTC Pool yVault
        _addVault(0x7047F90229a057C13BF847C0744D646CFb6c9E1A); // Curve renBTC Pool yVault
        _addVault(0xe9Dc63083c464d6EDcCFf23444fF3CFc6886f6FB); // Curve oBTC Pool yVault
        _addVault(0x3c5DF3077BcF800640B5DAE8c91106575a4826E6); // Curve pBTC Pool yVault
        _addVault(0x23D3D0f1c697247d5e0a9efB37d8b0ED0C464f7f); // Curve tBTC Pool yVault
        _addVault(0xB4AdA607B9d6b2c9Ee07A275e9616B84AC560139); // Curve FRAX Pool yVault
        _addVault(0x5fA5B62c8AF877CB37031e0a3B2f34A78e3C56A6); // Curve LUSD Pool yVault
        _addVault(0xb4D1Be44BfF40ad6e506edf43156577a3f8672eC); // Curve SAAVE Pool yVault
        _addVault(0x8fA3A9ecd9EFb07A8CE90A6eb014CF3c0E3B32Ef); // Curve BBTC Pool yVault
        _addVault(0x6Ede7F19df5df6EF23bD5B9CeDb651580Bdf56Ca); // Curve BUSD Pool yVault
        _addVault(0x2994529C0652D127b7842094103715ec5299bBed); // yearn Curve.fi yDAI/yUSDC/yUSDT/yBUSD
        _addVault(0xD6Ea40597Be05c201845c0bFd2e96A60bACde267); // Curve Compound Pool yVault
    }

    /* ============ External Functions ============ */

    /**
     * Adds/deletes Vaults
     * @param _vaults             List of Vault addresses
     * @param _values             List of booleans. True means valid vault
     *
     */
    function updateVaults(address[] calldata _vaults, bool[] calldata _values) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _vaults.length; i++) {
            if (_values[i]) {
                _addVault(_vaults[i]);
            } else {
                _removeVault(_vaults[i]);
            }
        }
    }

    function getAllVaults() external view override returns (address[] memory) {
        return vaultList;
    }

    /* ============ Internal Functions ============ */

    function _addVault(address _vault) private {
        vaultList.push(_vault);
        vaults[_vault] = true;
    }

    function _removeVault(address _vault) private {
        (bool found, uint256 index) = _findVault(_vault);
        if (found) {
            vaultList[index] = vaultList[vaultList.length - 1];
            vaultList.pop();
            vaults[_vault] = false;
        }
    }

    function _findVault(address _vault) private view returns (bool, uint256) {
        for (uint256 i = 0; i < vaultList.length; i++) {
            if (vaultList[i] == _vault) {
                return (true, i);
            }
        }
        return (false, 0);
    }
}
