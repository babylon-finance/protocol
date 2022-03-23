// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {IBabController} from './interfaces/IBabController.sol';
import {IHeart} from './interfaces/IHeart.sol';
import {IHypervisor} from './interfaces/IHypervisor.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IGovernor} from './interfaces/external/oz/IGovernor.sol';

import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {ControllerLib} from './lib/ControllerLib.sol';

/**
 * @title HeartViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve heart and governance information effectively
 */
contract HeartViewer {
    using SafeMath for uint256;
    using ControllerLib for IBabController;

    /* ============ Modifiers ============ */

    /* ============ Variables ============ */

    IBabController public immutable controller;
    IGovernor public immutable governor;
    IHeart public immutable heart;
    IGarden public heartGarden;
    IHypervisor public constant visor = IHypervisor(0xF19F91d7889668A533F14d076aDc187be781a458);
    IHypervisor public constant visor_full = IHypervisor(0x5e6c481dE496554b66657Dd1CA1F70C61cf11660);

    /* ============ External function  ============ */

    constructor(
        IBabController _controller,
        IGovernor _governor,
        IHeart _heart
    ) {
        require(address(_controller) != address(0), 'Controller must exist');
        require(address(_governor) != address(0), 'Governor must exist');

        controller = _controller;
        governor = _governor;
        heart = _heart;
    }

    function setHeartGarden(IGarden _heartGarden) external {
        controller.onlyGovernanceOrEmergency();
        heartGarden = _heartGarden;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets all the heart details in one view call
     */
    function getAllHeartDetails()
        external
        view
        returns (
            address[2] memory, // address of the heart garden
            uint256[7] memory, // total stats
            uint256[] memory, // fee weights
            address[] memory, // voted gardens
            uint256[] memory, // garden weights
            uint256[2] memory, // weekly babl reward
            uint256[2] memory, // dates
            uint256[2] memory // liquidity
        )
    {
        (uint256 wethAmount, uint256 bablAmount) = visor.getTotalAmounts();
        (uint256 wethAmountF, uint256 bablAmountF) = visor_full.getTotalAmounts();

        return (
            [address(heartGarden), heart.assetToLend()],
            heart.getTotalStats(),
            heart.getFeeDistributionWeights(),
            heart.getVotedGardens(),
            heart.getGardenWeights(),
            [heart.bablRewardLeft(), heart.weeklyRewardAmount()],
            [heart.lastPumpAt(), heart.lastVotesAt()],
            [wethAmount.add(wethAmountF), bablAmount.add(bablAmountF)]
        );
    }

    function getBondDiscounts(address[] calldata _assets) external view returns (uint256[] memory) {
        uint256[] memory discounts = new uint256[](_assets.length);
        for (uint256 i = 0; i < _assets.length; i++) {
            discounts[i] = heart.bondAssets(_assets[i]);
        }
        return discounts;
    }

    function getGovernanceProposals(uint256[] calldata _ids)
        external
        view
        returns (
            address[] memory, // proposers
            uint256[] memory, // endBlocks
            uint256[] memory, // for votes - against votes
            uint256[] memory // state
        )
    {
        address[] memory proposers = new address[](_ids.length);
        uint256[] memory endBlocks = new uint256[](_ids.length);
        uint256[] memory votesA = new uint256[](_ids.length);
        uint256[] memory stateA = new uint256[](_ids.length);
        for (uint256 i = 0; i < _ids.length; i++) {
            (address proposer, uint256[3] memory data) = _getProposalInfo(_ids[i]);
            proposers[i] = proposer;
            endBlocks[i] = data[0];
            votesA[i] = data[1];
            stateA[i] = data[2];
        }
        return (proposers, endBlocks, votesA, stateA);
    }

    /* ============ Private Functions ============ */

    function _getProposalInfo(uint256 _proposalId) internal view returns (address, uint256[3] memory) {
        (, address proposer, , , uint256 endBlock, uint256 forVotes, uint256 againstVotes, , , ) =
            governor.proposals(_proposalId);
        return (proposer, [endBlock, forVotes.sub(againstVotes), uint256(governor.state(_proposalId))]);
    }
}
