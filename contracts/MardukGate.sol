// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.7.6;
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {ERC721} from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IBabController} from './interfaces/IBabController.sol';
import {IMardukGate} from './interfaces/IMardukGate.sol';
import {IIshtarGate} from './interfaces/IIshtarGate.sol';
import {IGarden} from './interfaces/IGarden.sol';

/**
 * @title MardukGate
 * @author Babylon Finance
 *
 * Contract that implements guestlists without NFT and checks Ishtar Gate when needed
 */
contract MardukGate is IMardukGate, Ownable {
    using SafeMath for uint256;

    /* ============ Events ============ */

    event GardenAccess(address indexed _member, address indexed _garden, uint8 _permission);
    event GardenCreationPower(address indexed _member, bool _creation);

    /* ============ State Variables ============ */

    // Address of the Controller contract
    IBabController public controller;
    IIshtarGate private ishtarGate;

    uint256 public override maxNumberOfInvites;

    // Permissions by community user
    mapping(address => mapping(address => uint8)) public permissionsByCommunity;
    mapping(address => mapping(address => bool)) public isOverriden;
    mapping(address => bool) public canCreateAGarden;
    mapping(address => bool) public betaAccess;
    mapping(address => uint256) public gardenAccessCount;

    mapping(address => address[]) public invitesPerGarden;

    uint8 public constant NONE = 0;
    uint8 public constant JUST_LP = 1;
    uint8 public constant STEWARD = 2;
    uint8 public constant STRATEGIST = 3;

    /* ============ Modifiers ============ */

    modifier onlyGardenCreator(address _garden) {
        require(address(_garden) != address(0), 'Garden must exist');
        IGarden garden = IGarden(_garden);
        require(garden.controller() == controller, 'Controller must match');
        require(_isCreator(IGarden(_garden), msg.sender), 'Only creator can give access to garden');
        require(IBabController(controller).isGarden(address(_garden)));
        require(gardenAccessCount[_garden] <= maxNumberOfInvites, 'The number of contributors must be below the limit');
        _;
    }

    /* ============ Constructor ============ */

    /**
     * Sets the protocol controller
     *
     * @param _controller         Address of controller contract
     * @param _ishtarGate         Address of the ishtar gate
     */
    constructor(IBabController _controller, IIshtarGate _ishtarGate) {
        require(address(_controller) != address(0), 'Controller must exist');
        require(address(_ishtarGate) != address(0), 'Ishtar Gate must exist');
        controller = _controller;
        ishtarGate = _ishtarGate;
        maxNumberOfInvites = ishtarGate.maxNumberOfInvites() > 0 ? ishtarGate.maxNumberOfInvites() : 100;
    }

    /* ============ External Functions ============ */

    /**
     * Changs the number of invites we are going to give per garden
     *
     * @param _maxNumberOfInvites               New max number of invites per garden
     */
    function setMaxNumberOfInvites(uint256 _maxNumberOfInvites) external override onlyOwner {
        require(_maxNumberOfInvites > maxNumberOfInvites, 'Invites must be higher');
        maxNumberOfInvites = _maxNumberOfInvites;
    }

    /**
     * Gives user access to a specific garden via Marduk Gate
     *
     * @param _user               Address of the user
     * @param _garden             Community that the gate grants access to
     * @param _permission        Permissions of what user can do in the community
     */
    function setGardenAccess(
        address _user,
        address _garden,
        uint8 _permission
    ) external override returns (uint256) {
        require(
            _isCreator(IGarden(_garden), msg.sender) || msg.sender == address(_garden),
            'Only creator or garden can change params'
        );
        require(address(_user) != address(0), 'User must exist');
        return _setIndividualGardenAccess(_user, _garden, _permission);
    }

    /**
     * Uses Marduk Gate to grant a list of users with permissions to a specific garden
     *
     * @param _garden             Community that the gate grants access to
     * @param _users              Addresses of the users
     * @param _perms              List of permissions of what each user can do in the community
     */
    function grantGardenAccessBatch(
        address _garden,
        address[] calldata _users,
        uint8[] calldata _perms
    ) external override onlyGardenCreator(_garden) returns (bool) {
        require(_users.length == _perms.length, 'Permissions and users must match');
        for (uint8 i = 0; i < _users.length; i++) {
            require(address(_users[i]) != address(0), 'User must exist');
            _setIndividualGardenAccess(_users[i], _garden, _perms[i]);
        }
        return true;
    }

    /**
     * Grants an user/remove garden creation capabilities via Marduk Gate.
     *
     * @param _user               Address of the user
     * @param _canCreate          Boolean with permissions as to whether the user can create gardens
     */
    function setCreatorPermissions(address _user, bool _canCreate) external override onlyOwner returns (uint256) {
        return _setCreatorPermissions(_user, _canCreate);
    }

    /**
     * Grants a list of users with permissions to create gardens
     *
     * @param _users              Addresses of the users
     * @param _perms              Lists of booleans
     */
    function grantCreatorsInBatch(address[] calldata _users, bool[] calldata _perms)
        external
        override
        onlyOwner
        returns (bool)
    {
        require(_users.length == _perms.length, 'Permissions and users must match');
        for (uint8 i = 0; i < _users.length; i++) {
            _setCreatorPermissions(_users[i], _perms[i]);
        }
        return true;
    }

    /* ============ Getter Functions ============ */

    /**
     * Check if a user can access the beta
     *
     * @param _user                     Address of the user
     * @return bool               Whether or not the user can access the beta
     */
    function canAccessBeta(address _user) external view override returns (bool) {
        return IERC721(address(ishtarGate)).balanceOf(_user) > 0 || betaAccess[_user];
    }

    /**
     * Check if a user can create gardens
     *
     * @param _user                     Address of the user
     * @return _canCreate               Whether or not the user can create
     */
    function canCreate(address _user) external view override returns (bool) {
        return ishtarGate.canCreate(_user) || canCreateAGarden[_user];
    }

    /**
     * Check if a user can join a specific garden
     *
     * @param _garden                     Address of the _garden
     * @param _user                       Address of the user
     * @return _canJoin                   Whether or not the user can join
     */
    function canJoinAGarden(address _garden, address _user) external view override returns (bool) {
        if (_isCreator(IGarden(_garden), _user)) {
            return true;
        }
        if (isOverriden[_garden][_user]) {
            return permissionsByCommunity[_garden][_user] >= JUST_LP;
        }
        return ishtarGate.canJoinAGarden(_garden, _user);
    }

    /**
     * Check if a user can vote in a specific garden
     *
     * @param _garden                     Address of the _garden
     * @param _user                       Address of the user
     * @return _canVote                   Whether or not the user can vote
     */
    function canVoteInAGarden(address _garden, address _user) external view override returns (bool) {
        if (_isCreator(IGarden(_garden), _user)) {
            return true;
        }
        if (isOverriden[_garden][_user]) {
            return permissionsByCommunity[_garden][_user] >= STEWARD;
        }
        return ishtarGate.canVoteInAGarden(_garden, _user);
    }

    /**
     * Check if a user can add strategies in a specific garden
     *
     * @param _garden                     Address of the _garden
     * @param _user                       Address of the user
     * @return _canStrategize             Whether or not the user can create strategies
     */
    function canAddStrategiesInAGarden(address _garden, address _user) external view override returns (bool) {
        if (_isCreator(IGarden(_garden), _user)) {
            return true;
        }
        if (isOverriden[_garden][_user]) {
            return permissionsByCommunity[_garden][_user] >= STRATEGIST;
        }
        return ishtarGate.canAddStrategiesInAGarden(_garden, _user);
    }

    /**
     * Returns all the invites sent from a specific garden
     *
     * @param _garden                     Address of the _garden
     * @return address[]                  All the invites sent
     */
    function getInvitesPerGarden(address _garden) external view returns (address[] memory) {
        return invitesPerGarden[_garden];
    }

    /* ============ Internal Functions ============ */

    /**
     * Grants access to an user and gives him access to a specific garden
     *
     * @param _user               Address of the user
     * @param _garden             Community that the gate grants access to
     * @param _permission        Permissions of what user can do in the community
     */
    function _setIndividualGardenAccess(
        address _user,
        address _garden,
        uint8 _permission
    ) private returns (uint256) {
        require(_permission <= 3, 'Permission out of bounds');
        if (_permission > 0 && permissionsByCommunity[_garden][_user] == 0) {
            require(gardenAccessCount[_garden] < maxNumberOfInvites, 'Max Number of invites reached');
            gardenAccessCount[_garden] = gardenAccessCount[_garden].add(1);
            invitesPerGarden[_garden].push(_user);
        }
        if (_permission == 0 && permissionsByCommunity[_garden][_user] > 0) {
            gardenAccessCount[_garden] = gardenAccessCount[_garden].sub(1);
        }
        permissionsByCommunity[_garden][_user] = _permission;
        isOverriden[_garden][_user] = true;
        betaAccess[_user] = true;
        emit GardenAccess(_user, _garden, _permission);
        return 0;
    }

    /**
     * Grants access to an user and give/remove him garden creation capabilities.
     *
     * @param _user               Address of the user
     * @param _canCreate          Boolean with permissions as to whether the user can create gardens
     */
    function _setCreatorPermissions(address _user, bool _canCreate) private returns (uint256) {
        require(address(_user) != address(0), 'User must exist');
        canCreateAGarden[_user] = _canCreate;
        emit GardenCreationPower(_user, _canCreate);
        return 0;
    }

    // Checks if an address is a creator
    function _isCreator(IGarden _garden, address _member) private view returns (bool) {
        return
            _member != address(0) &&
            (_garden.extraCreators(0) == _member ||
                _garden.extraCreators(1) == _member ||
                _garden.extraCreators(2) == _member ||
                _garden.extraCreators(3) == _member ||
                _member == _garden.creator());
    }
}
