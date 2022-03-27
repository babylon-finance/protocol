// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {LowGasSafeMath as SafeMath} from '../lib/LowGasSafeMath.sol';
import {PreciseUnitMath} from '../lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from '../lib/SafeDecimalMath.sol';
import {Math} from '../lib/Math.sol';

import {IRewardsDistributor} from '../interfaces/IRewardsDistributor.sol';
import {IBabController} from '../interfaces/IBabController.sol';
import {IGardenValuer} from '../interfaces/IGardenValuer.sol';
import {IGarden} from '../interfaces/IGarden.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IMardukGate} from '../interfaces/IMardukGate.sol';
import {IGardenNFT} from '../interfaces/IGardenNFT.sol';
import {IStrategyNFT} from '../interfaces/IStrategyNFT.sol';
import {IPriceOracle} from '../interfaces/IPriceOracle.sol';
import {IGardenViewer, IStrategyViewer} from '../interfaces/IViewer.sol';

/**
 * @title GardenViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve garden information effectively
 */
contract StrategyViewer is IStrategyViewer {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using Math for int256;
    using SafeDecimalMath for uint256;

    IBabController private immutable controller;

    constructor(IBabController _controller) {
        controller = _controller;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets complete strategy details
     *
     * @param _strategy            Address of the strategy to fetch
     * @return                     All strategy details
     */
    function getCompleteStrategy(address _strategy)
        external
        view
        override
        returns (
            address,
            string memory,
            uint256[16] memory,
            bool[] memory,
            uint256[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        bool[] memory status = new bool[](3);
        uint256[] memory ts = new uint256[](4);
        // ts[0]: executedAt, ts[1]: exitedAt, ts[2]: updatedAt
        (, status[0], status[1], status[2], ts[0], ts[1], ts[2]) = strategy.getStrategyState();
        uint256 rewards =
            ts[1] != 0 ? IRewardsDistributor(controller.rewardsDistributor()).getStrategyRewards(_strategy) : 0;
        ts[3] = strategy.enteredCooldownAt();
        return (
            strategy.strategist(),
            IStrategyNFT(controller.strategyNFT()).getStrategyName(_strategy),
            [
                strategy.getOperationsCount(),
                strategy.stake(),
                strategy.totalPositiveVotes(),
                strategy.totalNegativeVotes(),
                strategy.capitalAllocated(),
                strategy.capitalReturned(),
                strategy.duration(),
                strategy.expectedReturn(),
                strategy.maxCapitalRequested(),
                strategy.enteredAt(),
                strategy.getNAV(),
                rewards,
                strategy.maxAllocationPercentage(),
                strategy.maxGasFeePercentage(),
                strategy.maxTradeSlippagePercentage(),
                strategy.isStrategyActive()
                    ? IRewardsDistributor(controller.rewardsDistributor()).estimateStrategyRewards(_strategy)
                    : 0
            ],
            status,
            ts
        );
    }

    function getOperationsStrategy(address _strategy)
        external
        view
        override
        returns (
            uint8[] memory,
            address[] memory,
            bytes[] memory
        )
    {
        IStrategy strategy = IStrategy(_strategy);
        uint256 count = strategy.getOperationsCount();
        uint8[] memory types = new uint8[](count);
        address[] memory integrations = new address[](count);
        bytes[] memory datas = new bytes[](count);

        for (uint8 i = 0; i < count; i++) {
            (types[i], integrations[i], datas[i]) = strategy.getOperationByIndex(i);
        }
        return (types, integrations, datas);
    }

    function getUserStrategyActions(address[] memory _strategies, address _user)
        external
        view
        override
        returns (uint256, uint256)
    {
        uint256 strategiesCreated;
        uint256 totalVotes;
        for (uint8 i = 0; i < _strategies.length; i++) {
            IStrategy strategy = IStrategy(_strategies[i]);
            if (strategy.strategist() == _user) {
                strategiesCreated = strategiesCreated.add(1);
            }
            int256 votes = strategy.getUserVotes(_user);
            if (votes != 0) {
                totalVotes = totalVotes.add(uint256(Math.abs(votes)));
            }
        }
        return (strategiesCreated, totalVotes);
    }

    /* ============ Private Functions ============ */
}
