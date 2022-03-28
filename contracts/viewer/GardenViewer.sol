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
import {IGardenViewer} from '../interfaces/IViewer.sol';

/**
 * @title GardenViewer
 * @author Babylon Finance
 *
 * Class that holds common view functions to retrieve garden information effectively
 */
contract GardenViewer {
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
        bool isZero = _user == address(0);
        return (
            !IGarden(_garden).privateGarden() || (!isZero && gate.canJoinAGarden(_garden, _user)),
            IGarden(_garden).publicStewards() || (!isZero && gate.canVoteInAGarden(_garden, _user)),
            IGarden(_garden).publicStrategists() || (!isZero && gate.canAddStrategiesInAGarden(_garden, _user))
        );
    }

    function getGardensUser(address _user, uint256 _offset)
        external
        view
        returns (
            address[] memory,
            bool[] memory,
            IGardenViewer.PartialGardenInfo[] memory
        )
    {
        address[] memory gardens = controller.getGardens();
        address[] memory userGardens = new address[](50);
        bool[] memory hasUserDeposited = new bool[](50);
        IGardenViewer.PartialGardenInfo[] memory info = new IGardenViewer.PartialGardenInfo[](50);
        uint256 limit = gardens.length <= 50 ? gardens.length : _offset.add(50);
        limit = limit < gardens.length ? limit : gardens.length;
        uint8 resultIndex;
        for (uint256 i = _offset; i < limit; i++) {
            (bool depositPermission, , ) = getGardenPermissions(gardens[i], _user);
            if (depositPermission) {
                userGardens[resultIndex] = gardens[i];
                hasUserDeposited[resultIndex] = _user != address(0) ? IERC20(gardens[i]).balanceOf(_user) > 0 : false;
                IGarden garden = IGarden(gardens[i]);
                info[resultIndex] = IGardenViewer.PartialGardenInfo(
                    gardens[i],
                    garden.name(),
                    !garden.privateGarden(),
                    garden.verifiedCategory(),
                    garden.totalContributors(),
                    garden.reserveAsset(),
                    garden.totalSupply().mul(garden.lastPricePerShare()).div(1e18)
                );
                resultIndex = resultIndex + 1;
            }
        }
        return (userGardens, hasUserDeposited, info);
    }

    function getGardenUserAvgPricePerShare(IGarden _garden, address _user) public view returns (uint256) {
        (, , , , , , uint256 totalDeposits, , ) = _garden.getContributor(_user);

        // Avg price per user share = deposits / garden tokens
        // contributor[0] -> Deposits (ERC20 reserveAsset with X decimals)
        // contributor[1] -> Balance (Garden tokens) with 18 decimals
        return totalDeposits > 0 ? totalDeposits.preciseDiv(_garden.balanceOf(_user)) : 0;
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

    function getContributor(IGarden _garden, address _user) internal view returns (uint256[10] memory) {
        (
            uint256 lastDepositAt,
            uint256 initialDepositAt,
            uint256 claimedAt,
            uint256 claimedBABL,
            uint256 claimedRewards,
            uint256 withdrawnSince,
            uint256 totalDeposits,
            ,
            uint256 lockedBalance
        ) = _garden.getContributor(_user);
        return [
            lastDepositAt,
            initialDepositAt,
            claimedAt,
            claimedBABL,
            claimedRewards,
            totalDeposits > withdrawnSince ? totalDeposits.sub(withdrawnSince) : 0,
            _garden.balanceOf(_user),
            lockedBalance,
            0,
            getGardenUserAvgPricePerShare(_garden, _user)
        ];
    }

    function getContributionAndRewards(IGarden _garden, address _user)
        external
        view
        returns (
            uint256[10] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        return (
            getContributor(_garden, _user),
            IRewardsDistributor(controller.rewardsDistributor()).getRewards(
                address(_garden),
                _user,
                _garden.getFinalizedStrategies()
            ),
            _estimateUserRewards(_user, _garden.getStrategies())
        );
    }

    function getPriceAndLiquidity(address _tokenIn, address _reserveAsset) external view returns (uint256, uint256) {
        return (
            IPriceOracle(controller.priceOracle()).getPrice(_tokenIn, _reserveAsset),
            _getUniswapHighestLiquidity(_tokenIn, _reserveAsset)
        );
    }

    function getAllProphets(address _address) external view returns (uint256[] memory) {
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
        (, , , , , , uint256 totalDeposits, , ) = garden.getContributor(_user);

        // Avg price per user share = deposits / garden tokens
        return totalDeposits > 0 ? totalDeposits.preciseDiv(garden.balanceOf(_user)) : 0;
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
