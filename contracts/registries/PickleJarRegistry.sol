// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;

import {IBabController} from '../interfaces/IBabController.sol';
import {IPickleJarRegistry} from '../interfaces/IPickleJarRegistry.sol';

import {ControllerLib} from '../lib/ControllerLib.sol';

/**
 * @title PickleJarRegistry
 * @author Babylon Finance Protocol
 *
 * Abstraction for all the different Jars
 */
contract PickleJarRegistry is IPickleJarRegistry {
    using ControllerLib for IBabController;

    /* ============ Constants ============ */

    IBabController public immutable controller;

    /* ============ State Variables ============ */

    // Mapping of valid jars
    mapping(address => bool) public override jars;
    mapping(address => bool) public override isUniv3;
    address[] public jarList;

    /* ============ Modifiers ============ */

    /* ============ Constructor ============ */

    constructor(IBabController _controller) {
        require(address(_controller) != address(0), 'Controller is not valid');
        controller = _controller;
        // https://github.com/pickle-finance/contracts
        _addJar(0x68d14d66B2B0d6E157c06Dc8Fefa3D8ba0e66a89, false);
        _addJar(0x2E35392F4c36EBa7eCAFE4de34199b2373Af22ec, false);
        _addJar(0x1BB74b5DdC1f4fC91D6f9E7906cf68bc93538e33, false);
        _addJar(0x77C8A58D940a322Aea02dBc8EE4A30350D4239AD, false);
        _addJar(0xCbA1FE4Fdbd90531EFD929F1A1831F38e91cff1e, false);
        _addJar(0x65B2532474f717D5A8ba38078B78106D56118bbb, false);
        _addJar(0x55282dA27a3a02ffe599f6D11314D239dAC89135, false);
        _addJar(0x8c2D16B7F6D3F989eb4878EcF13D695A7d504E43, false);
        _addJar(0xa7a37aE5Cb163a3147DE83F15e15D8E5f94D6bCE, false);
        _addJar(0xde74b6c547bd574c3527316a2eE30cd8F6041525, false);
        _addJar(0x3261D9408604CC8607b687980D40135aFA26FfED, false);
        _addJar(0x5Eff6d166D66BacBC1BF52E2C54dD391AE6b1f48, false);
        _addJar(0x3Bcd97dCA7b1CED292687c97702725F37af01CaC, false);
        _addJar(0xaFB2FE266c215B5aAe9c4a9DaDC325cC7a497230, false);
        _addJar(0xF303B35D5bCb4d9ED20fB122F5E268211dEc0EBd, false);
        _addJar(0x7C8de3eE2244207A54b57f45286c9eE1465fee9f, false);
        _addJar(0x1ed1fD33b62bEa268e527A622108fe0eE0104C07, false);
        _addJar(0x1CF137F651D8f0A4009deD168B442ea2E870323A, false);
        _addJar(0xECb520217DccC712448338B0BB9b08Ce75AD61AE, false);
        _addJar(0xC1513C1b0B359Bc5aCF7b772100061217838768B, false);
        _addJar(0xCeD67a187b923F0E5ebcc77C7f2F7da20099e378, false);
        _addJar(0x927e3bCBD329e89A8765B52950861482f0B227c4, false);
        _addJar(0x9eb0aAd5Bb943D3b2F7603Deb772faa35f60aDF9, false);
        _addJar(0xDCfAE44244B3fABb5b351b01Dc9f050E589cF24F, false);
        _addJar(0xe6487033F5C8e2b4726AF54CA1449FEC18Bd1484, false);
        _addJar(0xEB801AB73E9A2A482aA48CaCA13B1954028F4c94, false);
        _addJar(0x4fFe73Cf2EEf5E8C8E0E10160bCe440a029166D2, false);
        _addJar(0x822Ba8e3b95A26264Cd726828Af47Ee150729afd, false);
        _addJar(0x729C6248f9B1Ce62B3d5e31D4eE7EE95cAB32dfD, false);
        _addJar(0x993f35FaF4AEA39e1dfF28f45098429E0c87126C, false);
        _addJar(0xdB84a6A48881545E8595218b7a2A3c9bd28498aE, false);
        _addJar(0x1Bf62aCb8603Ef7F3A0DFAF79b25202fe1FAEE06, false);
        _addJar(0xeb8174F94FDAcCB099422d9A816B8E17d5e393E3, false);
        _addJar(0x1d92e1702D7054f74eAC3a9569AeB87FC93e101D, false);
        _addJar(0x4E9806345fb39FFebd70A01f177A675805019ba8, false);
        _addJar(0x0989a227E7c50311f7De61e5e61F7c28Df8936f0, false);
        _addJar(0xF1478A8387C449c55708a3ec11c143c35daf5E74, false);
        _addJar(0xB245280Fd1795f5068DEf8E8f32DB7846b030b2B, false);
        _addJar(0xD38A7E64677d92D3966285fa3aD1dc68A02b7c33, false);
        _addJar(0x506748d736b77f51c5b490e4aC6c26B8c3975b14, true);
        _addJar(0x1c5Dbb5d9864738e84c126782460C18828859648, false);
        _addJar(0xc97f3fd224d90609831a2B74b46642aC43afE5ee, false);
        _addJar(0xBc57294Fc20bD23983dB598fa6B3f306aA1a414f, false);
        _addJar(0x69CC22B240bdcDf4A33c7B3D04a660D4cF714370, false);
        _addJar(0xb4EBc2C371182DeEa04B2264B9ff5AC4F0159C69, false);
        _addJar(0xe7b69a17B3531d01FCEAd66FaF7d9f7655469267, true);
        _addJar(0x8CA1D047541FE183aE7b5d80766eC6d5cEeb942A, true);
        _addJar(0x3b79f29d7979D7DE22A0d09098e898157ea32dD5, true);
        _addJar(0x0A3a5764945E29E38408637bC659981f0172b961, true);
        _addJar(0x563c77b40c7f08bA735426393Cf5f0e527D16C10, true);
        _addJar(0xAaCDaAad9a9425bE2d666d08F741bE4F081C7ab1, true);
        _addJar(0x575a9E386c33732880DEF8BE1BAD9dbc5dDDf7D7, true);
        _addJar(0x7f3514CBC6825410Ca3fA4deA41d46964a953Afb, true);
        _addJar(0xf0Fb82757B9f8A3A3AE3524e385E2E9039633948, true);
        _addJar(0x49ED0e6B438430CEEdDa8C6d06B6A2797aFA81cA, true);
        _addJar(0x81740AAc02ae2F3c61D5a0c012b3e18f9dc02b5c, false);
        _addJar(0x363e7CD14AEcf4f7d0e66Ae1DEff830343D760a7, false);
    }

    /* ============ External Functions ============ */

    /**
     * Adds/deletes jars
     * @param _jars             List of jar addresses
     * @param _values           List of booleans. True means valid jar
     * @param _uniflags         List of booleans. True means univ3 jar
     *
     */
    function updateJars(
        address[] calldata _jars,
        bool[] calldata _values,
        bool[] calldata _uniflags
    ) external override {
        controller.onlyGovernanceOrEmergency();
        for (uint256 i = 0; i < _jars.length; i++) {
            if (_values[i]) {
                _addJar(_jars[i], _uniflags[i]);
            } else {
                _removeJar(_jars[i]);
            }
        }
    }

    function getAllJars() external view override returns (address[] memory) {
        return jarList;
    }

    /* ============ Internal Functions ============ */

    function _addJar(address _jar, bool _univ3) private {
        jarList.push(_jar);
        jars[_jar] = true;
        isUniv3[_jar] = _univ3;
    }

    function _removeJar(address _jar) private {
        (bool found, uint256 index) = _findJar(_jar);
        if (found) {
            jarList[index] = jarList[jarList.length - 1];
            jarList.pop();
            jars[_jar] = false;
            isUniv3[_jar] = false;
        }
    }

    function _findJar(address _jar) private view returns (bool, uint256) {
        for (uint256 i = 0; i < jarList.length; i++) {
            if (jarList[i] == _jar) {
                return (true, i);
            }
        }
        return (false, 0);
    }
}
