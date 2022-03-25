// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
pragma abicoder v2;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {LowGasSafeMath as SafeMath} from './lib/LowGasSafeMath.sol';
import {PreciseUnitMath} from './lib/PreciseUnitMath.sol';
import {SafeDecimalMath} from './lib/SafeDecimalMath.sol';
import {IRewardsDistributor} from './interfaces/IRewardsDistributor.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IGardenValuer} from './interfaces/IGardenValuer.sol';
import {IGarden} from './interfaces/IGarden.sol';
import {IStrategy} from './interfaces/IStrategy.sol';
import {IMardukGate} from './interfaces/IMardukGate.sol';
import {IGardenNFT} from './interfaces/IGardenNFT.sol';
import {IStrategyNFT} from './interfaces/IStrategyNFT.sol';
import {IPriceOracle} from './interfaces/IPriceOracle.sol';
import {Math} from './lib/Math.sol';

/**
 * @title BabylonViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve garden information effectively
 */
contract BabylonViewer {
    using SafeMath for uint256;
    using PreciseUnitMath for uint256;
    using Math for int256;
    using SafeDecimalMath for uint256;

    IBabController private immutable controller;
    uint24 internal constant FEE_LOW = 500;
    uint24 internal constant FEE_MEDIUM = 3000;
    uint24 internal constant FEE_HIGH = 10000;
    IUniswapV3Factory internal constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    constructor(IBabController _controller) {
        controller = _controller;
    }

    /* ============ External Getter Functions ============ */

    /**
     * Gets garden principal
     *
     * @param _garden            Address of the garden to fetch
     * @return                   Garden principal
     */
    function getGardenPrincipal(address _garden) public view returns (uint256) {
        IGarden garden = IGarden(_garden);
        IERC20 reserveAsset = IERC20(garden.reserveAsset());
        uint256 principal = reserveAsset.balanceOf(address(garden)).sub(garden.reserveAssetRewardsSetAside());
        uint256 protocolMgmtFee = IBabController(controller).protocolManagementFee();
        address[] memory strategies = garden.getStrategies();
        for (uint256 i = 0; i < strategies.length; i++) {
            IStrategy strategy = IStrategy(strategies[i]);
            principal = principal.add(strategy.capitalAllocated()).add(
                protocolMgmtFee.preciseMul(strategy.capitalAllocated())
            );
        }
        address[] memory finalizedStrategies = garden.getFinalizedStrategies();
        for (uint256 i = 0; i < finalizedStrategies.length; i++) {
            IStrategy strategy = IStrategy(finalizedStrategies[i]);
            principal = principal.add(protocolMgmtFee.preciseMul(strategy.capitalAllocated()));
        }
        principal = principal.add(garden.totalKeeperFees());
        int256 absoluteReturns = garden.absoluteReturns();
        if (absoluteReturns > 0) {
            principal = principal > uint256(absoluteReturns) ? principal.sub(uint256(absoluteReturns)) : 0;
        } else {
            principal = principal.add(uint256(-absoluteReturns));
        }
        return principal;
    }

    /**
     * Gets garden details
     *
     * @param _garden            Address of the garden to fetch
     * @return                   Garden complete details
     */
    function getGardenDetails(address _garden)
        external
        view
        returns (
            string memory,
            string memory,
            address[5] memory,
            address,
            bool[4] memory,
            address[] memory,
            address[] memory,
            uint256[13] memory,
            uint256[10] memory,
            uint256[3] memory
        )
    {
        IGarden garden = IGarden(_garden);
        uint256 principal = getGardenPrincipal(_garden);
        uint256[] memory totalSupplyValuationAndSeed = new uint256[](4);
        totalSupplyValuationAndSeed[0] = IERC20(_garden).totalSupply();
        totalSupplyValuationAndSeed[1] = totalSupplyValuationAndSeed[0] > 0
            ? IGardenValuer(controller.gardenValuer()).calculateGardenValuation(_garden, garden.reserveAsset())
            : 0;
        totalSupplyValuationAndSeed[2] = _getGardenSeed(_garden);
        totalSupplyValuationAndSeed[3] = ERC20(garden.reserveAsset()).balanceOf(address(garden));
        if (totalSupplyValuationAndSeed[3] > garden.keeperDebt()) {
            totalSupplyValuationAndSeed[3] = totalSupplyValuationAndSeed[3].sub(garden.keeperDebt());
        }
        if (totalSupplyValuationAndSeed[3] > garden.reserveAssetRewardsSetAside()) {
            totalSupplyValuationAndSeed[3] = totalSupplyValuationAndSeed[3].sub(garden.reserveAssetRewardsSetAside());
        } else {
            totalSupplyValuationAndSeed[3] = 0;
        }

        uint256[3] memory profits = _getGardenProfitSharing(_garden);
        return (
            ERC20(_garden).name(),
            ERC20(_garden).symbol(),
            [
                garden.creator(),
                garden.extraCreators(0),
                garden.extraCreators(1),
                garden.extraCreators(2),
                garden.extraCreators(3)
            ],
            garden.reserveAsset(),
            [true, garden.privateGarden(), garden.publicStrategists(), garden.publicStewards()],
            garden.getStrategies(),
            garden.getFinalizedStrategies(),
            [
                garden.depositHardlock(),
                garden.minVotesQuorum(),
                garden.maxDepositLimit(),
                garden.minVoters(),
                garden.minStrategyDuration(),
                garden.maxStrategyDuration(),
                garden.strategyCooldownPeriod(),
                garden.minContribution(),
                garden.minLiquidityAsset(),
                garden.totalKeeperFees().add(garden.keeperDebt()),
                garden.pricePerShareDecayRate(),
                garden.pricePerShareDelta(),
                garden.verifiedCategory()
            ],
            [
                principal,
                garden.reserveAssetRewardsSetAside(),
                uint256(garden.absoluteReturns()),
                garden.gardenInitializedAt(),
                garden.totalContributors(),
                garden.totalStake(),
                totalSupplyValuationAndSeed[1] > 0
                    ? totalSupplyValuationAndSeed[0].preciseMul(totalSupplyValuationAndSeed[1])
                    : 0,
                totalSupplyValuationAndSeed[0],
                totalSupplyValuationAndSeed[2],
                totalSupplyValuationAndSeed[3]
            ],
            profits
        );
    }

    /**
     * Gets complete strategy details
     *
     * @param _strategy            Address of the strategy to fetch
     * @return                     All strategy details
     */
    function getCompleteStrategy(address _strategy)
        external
        view
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
                strategy.isStrategyActive() ? _estimateStrategyRewards(_strategy) : 0
            ],
            status,
            ts
        );
    }

    function getOperationsStrategy(address _strategy)
        public
        view
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

    function getGardenPermissions(address _garden, address _user)
        public
        view
        returns (
            bool,
            bool,
            bool
        )
    {
        IMardukGate gate = IMardukGate(controller.mardukGate());
        return (
            gate.canJoinAGarden(_garden, _user) || (!IGarden(_garden).privateGarden()),
            gate.canVoteInAGarden(_garden, _user) || (IGarden(_garden).publicStewards()),
            gate.canAddStrategiesInAGarden(_garden, _user) || (IGarden(_garden).publicStrategists())
        );
    }

    struct PartialGardenInfo {
        address addr;
        string name;
        bool publicLP;
        uint256 verified;
        uint256 totalContributors;
        address reserveAsset;
        uint256 netAssetValue;
    }

    function getGardensUser(address _user, uint256 _offset)
        external
        view
        returns (
            address[] memory,
            bool[] memory,
            PartialGardenInfo[] memory
        )
    {
        address[] memory gardens = controller.getGardens();
        address[] memory userGardens = new address[](50);
        bool[] memory hasUserDeposited = new bool[](50);
        PartialGardenInfo[] memory data = new PartialGardenInfo[](50);
        uint256 limit = gardens.length <= 50 ? gardens.length : _offset.add(50);
        limit = limit < gardens.length ? limit : gardens.length;
        uint8 resultIndex;
        for (uint256 i = _offset; i < limit; i++) {
            (bool depositPermission, , ) = getGardenPermissions(gardens[i], _user);
            if (depositPermission) {
                userGardens[resultIndex] = gardens[i];
                hasUserDeposited[resultIndex] = _user != address(0) ? IERC20(gardens[i]).balanceOf(_user) > 0 : false;
                resultIndex = resultIndex + 1;
                IGarden garden = IGarden(gardens[i]);
                data[i] = PartialGardenInfo(
                    gardens[i],
                    garden.name(),
                    !garden.privateGarden(),
                    garden.verifiedCategory(),
                    garden.totalContributors(),
                    garden.reserveAsset(),
                    garden.totalSupply().mul(garden.lastPricePerShare())
                );
            }
        }
        return (userGardens, hasUserDeposited, data);
    }

    /**
     * Gets the number of tokens that can vote in this garden
     *
     * @param _garden  Garden to retrieve votes for
     * @param _members All members of a garden
     * @return uint256 Total number of tokens that can vote
     */
    function getPotentialVotes(address _garden, address[] calldata _members) external view returns (uint256) {
        IGarden garden = IGarden(_garden);
        if (garden.publicStewards()) {
            return IERC20(_garden).totalSupply();
        }
        uint256 total = 0;
        for (uint256 i = 0; i < _members.length; i++) {
            (bool canDeposit, bool canVote, ) = getGardenPermissions(_garden, _members[i]);
            if (canDeposit && canVote) {
                total = total.add(IERC20(_garden).balanceOf(_members[i]));
            }
        }
        return total;
    }

    function getUserStrategyActions(address[] memory _strategies, address _user)
        external
        view
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

    function getContributionAndRewards(address _garden, address _user)
        external
        view
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        IGarden garden = IGarden(_garden);
        uint256[] memory contribution = new uint256[](10);
        uint256[] memory pendingRewards = new uint256[](4);
        (
            contribution[0],
            contribution[1],
            contribution[2],
            contribution[3],
            contribution[4],
            contribution[5],
            ,
            ,
            contribution[8],

        ) = garden.getContributor(_user);
        contribution[6] = IERC20(_garden).balanceOf(_user);
        contribution[7] = garden.getLockedBalance(_user);
        uint256[] memory totalRewards =
            IRewardsDistributor(controller.rewardsDistributor()).getRewards(
                _garden,
                _user,
                garden.getFinalizedStrategies()
            );
        contribution[9] = _getGardenUserAvgPricePerShare(_garden, _user);
        pendingRewards = _estimateUserRewards(_user, garden.getStrategies());
        return (contribution, totalRewards, pendingRewards);
    }

    function getPriceAndLiquidity(address _tokenIn, address _reserveAsset) public view returns (uint256, uint256) {
        return (
            IPriceOracle(controller.priceOracle()).getPrice(_tokenIn, _reserveAsset),
            _getUniswapHighestLiquidity(_tokenIn, _reserveAsset)
        );
    }

    function getAllProphets(address _address) public view returns (uint256[] memory) {
        IERC721Enumerable prophets = IERC721Enumerable(0x26231A65EF80706307BbE71F032dc1e5Bf28ce43);
        uint256 prophetsNumber = prophets.balanceOf(_address);
        uint256[] memory prophetIds = new uint256[](prophetsNumber);
        for (uint256 i = 0; i < prophetsNumber; i++) {
            prophetIds[i] = prophets.tokenOfOwnerByIndex(_address, i);
        }
        return prophetIds;
    }

    /* ============ Private Functions ============ */

    function _getGardenSeed(address _garden) private view returns (uint256) {
        return IGardenNFT(controller.gardenNFT()).gardenSeeds(_garden);
    }

    function _getGardenProfitSharing(address _garden) private view returns (uint256[3] memory) {
        return IRewardsDistributor(controller.rewardsDistributor()).getGardenProfitsSharing(_garden);
    }

    function _getGardenUserAvgPricePerShare(address _garden, address _user) private view returns (uint256) {
        IGarden garden = IGarden(_garden);
        uint256[] memory contribution = new uint256[](2);
        (, , , , , contribution[0], contribution[1], , , ) = garden.getContributor(_user);

        // Avg price per user share = deposits / garden tokens
        // contributor[0] -> Deposits (ERC20 reserveAsset with X decimals)
        // contributor[1] -> Balance (Garden tokens) with 18 decimals
        return contribution[1] > 0 ? contribution[0].preciseDiv(contribution[1]) : 0;
    }

    function _getUniswapHighestLiquidity(address _sendToken, address _reserveAsset) private view returns (uint256) {
        // Exit if going to same asset
        if (_sendToken == _reserveAsset) {
            return 1e30;
        }
        (IUniswapV3Pool pool, ) = _getUniswapPoolWithHighestLiquidity(_sendToken, _reserveAsset);
        if (address(pool) == address(0)) {
            return 0;
        }
        uint256 poolLiquidity = uint256(pool.liquidity());
        uint256 liquidityInReserve;
        address denominator;

        if (pool.token0() == _reserveAsset) {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token1()).balanceOf(address(pool)));
            denominator = pool.token0();
        } else {
            liquidityInReserve = poolLiquidity.mul(poolLiquidity).div(ERC20(pool.token0()).balanceOf(address(pool)));
            denominator = pool.token1();
        }
        // Normalize to reserve asset
        if (denominator != _reserveAsset) {
            IPriceOracle oracle = IPriceOracle(IBabController(controller).priceOracle());
            uint256 price = oracle.getPrice(denominator, _reserveAsset);
            // price is always in 18 decimals
            // preciseMul returns in the same decimals than liquidityInReserve, so we have to normalize into reserve Asset decimals
            // normalization into reserveAsset decimals
            liquidityInReserve = SafeDecimalMath.normalizeAmountTokens(
                denominator,
                _reserveAsset,
                liquidityInReserve.preciseMul(price)
            );
        }
        return liquidityInReserve;
    }

    function _getUniswapPoolWithHighestLiquidity(address sendToken, address receiveToken)
        private
        view
        returns (IUniswapV3Pool pool, uint24 fee)
    {
        IUniswapV3Pool poolLow = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_LOW));
        IUniswapV3Pool poolMedium = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_MEDIUM));
        IUniswapV3Pool poolHigh = IUniswapV3Pool(uniswapFactory.getPool(sendToken, receiveToken, FEE_HIGH));

        uint128 liquidityLow = address(poolLow) != address(0) ? poolLow.liquidity() : 0;
        uint128 liquidityMedium = address(poolMedium) != address(0) ? poolMedium.liquidity() : 0;
        uint128 liquidityHigh = address(poolHigh) != address(0) ? poolHigh.liquidity() : 0;
        if (liquidityLow > liquidityMedium && liquidityLow >= liquidityHigh) {
            return (poolLow, FEE_LOW);
        }
        if (liquidityMedium > liquidityLow && liquidityMedium >= liquidityHigh) {
            return (poolMedium, FEE_MEDIUM);
        }
        return (poolHigh, FEE_HIGH);
    }

    /**
     * returns the estimated accrued BABL of a strategy
     */
    function _estimateStrategyRewards(address _strategy) private view returns (uint256) {
        return IRewardsDistributor(controller.rewardsDistributor()).estimateStrategyRewards(_strategy);
    }

    /**
     * returns the estimated accrued BABL for a user related to one strategy
     */
    function _estimateUserRewards(address _contributor, address[] memory _strategies)
        private
        view
        returns (uint256[] memory)
    {
        uint256[] memory totalRewards = new uint256[](8);
        address rewardsDistributor = address(controller.rewardsDistributor());
        for (uint256 i = 0; i < _strategies.length; i++) {
            uint256[] memory tempRewards = new uint256[](8);
            if (!IStrategy(_strategies[i]).isStrategyActive()) {
                continue;
            }
            tempRewards = IRewardsDistributor(rewardsDistributor).estimateUserRewards(_strategies[i], _contributor);
            for (uint256 j = 0; j < 8; j++) {
                totalRewards[j] = totalRewards[j].add(tempRewards[j]);
            }
        }
        return totalRewards;
    }
}
