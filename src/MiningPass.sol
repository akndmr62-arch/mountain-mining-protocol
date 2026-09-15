// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

/// @title MiningPass
/// @notice ERC-721 Mining Pass with protocol custody during active mining sessions.
contract MiningPass is ERC721, IERC721Receiver {
    error InvalidAddress();
    error UnauthorizedCaller(address caller);
    error NotTokenOwner(uint256 tokenId, address caller);
    error AlreadyMining(uint256 tokenId);
    error NotMining(uint256 tokenId);
    error InvalidMiningClass(uint8 classId);
    error InvalidDistributionPhase(uint8 phaseId);
    error TotalSupplyExceeded();
    error ClassSupplyExceeded(uint8 classId);
    error PhaseAllocationExceeded(uint8 phaseId);
    error CustodyTransferNotAllowed();
    error TokenInMining(uint256 tokenId);

    enum MiningClass {
        Stone,
        Obsidian,
        Iron,
        Steel,
        Titanium,
        Diamond,
        Mithril
    }

    enum DistributionPhase {
        Airdrop,
        EarlyAccess,
        PublicSale
    }

    struct MiningState {
        address miner;
        uint64 startedAt;
        bool active;
    }

    struct MiningPosition {
        address miner;
        uint64 startedAt;
        bool active;
        MiningClass classId;
        uint64 power;
    }

    uint256 public constant MAX_TOTAL_SUPPLY = 100_000;

    address public immutable miningEngine;
    address public immutable miningMinter;

    uint256 private _nextTokenId;
    bool private _lifecycleTransfer;

    mapping(uint256 tokenId => MiningClass classId) private _tokenClass;
    mapping(uint256 tokenId => MiningState state) private _miningStates;
    mapping(uint8 classId => uint32 count) private _classMinted;
    mapping(uint8 phaseId => uint32 count) private _phaseMinted;

    event MiningStarted(uint256 indexed tokenId, address indexed miner, uint256 timestamp);
    event MiningStopped(uint256 indexed tokenId, address indexed miner, uint256 timestamp);

    constructor(address miningEngine_, address miningMinter_) ERC721("Mountain Mining Pass", "MMPASS") {
        if (miningEngine_ == address(0) || miningMinter_ == address(0)) {
            revert InvalidAddress();
        }

        miningEngine = miningEngine_;
        miningMinter = miningMinter_;
    }

    modifier onlyMiningEngine() {
        if (msg.sender != miningEngine) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    modifier onlyMiningMinter() {
        if (msg.sender != miningMinter) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /// @notice Mints a new Mining Pass under bounded class and phase allocations.
    function mintMiningPass(address to, MiningClass classId, DistributionPhase phase)
        external
        onlyMiningMinter
        returns (uint256 tokenId)
    {
        if (to == address(0)) {
            revert InvalidAddress();
        }

        uint8 classIndex = uint8(classId);
        uint8 phaseIndex = uint8(phase);
        if (classIndex > uint8(MiningClass.Mithril)) {
            revert InvalidMiningClass(classIndex);
        }
        if (phaseIndex > uint8(DistributionPhase.PublicSale)) {
            revert InvalidDistributionPhase(phaseIndex);
        }

        if (_nextTokenId >= MAX_TOTAL_SUPPLY) {
            revert TotalSupplyExceeded();
        }

        if (_classMinted[classIndex] >= _classCap(classId)) {
            revert ClassSupplyExceeded(classIndex);
        }

        if (_phaseMinted[phaseIndex] >= _phaseCap(phase)) {
            revert PhaseAllocationExceeded(phaseIndex);
        }

        unchecked {
            tokenId = ++_nextTokenId;
            _classMinted[classIndex]++;
            _phaseMinted[phaseIndex]++;
        }

        _tokenClass[tokenId] = classId;
        _mint(to, tokenId);
    }

    /// @notice Starts mining by moving the NFT into protocol custody and recording the session start timestamp.
    function mine(uint256 tokenId) external {
        if (_ownerOf(tokenId) == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }

        MiningState storage state = _miningStates[tokenId];
        if (state.active) {
            revert AlreadyMining(tokenId);
        }

        address currentOwner = _ownerOf(tokenId);
        if (currentOwner != msg.sender) {
            revert NotTokenOwner(tokenId, msg.sender);
        }

        state.active = true;
        state.startedAt = uint64(block.timestamp);
        state.miner = msg.sender;

        _lifecycleTransfer = true;
        _transfer(msg.sender, address(this), tokenId);
        _lifecycleTransfer = false;

        emit MiningStarted(tokenId, msg.sender, block.timestamp);
    }

    /// @notice Releases a mining NFT back to its recorded miner and clears active mining state.
    function releaseFromMining(uint256 tokenId) external onlyMiningEngine {
        MiningState storage state = _miningStates[tokenId];
        if (!state.active) {
            revert NotMining(tokenId);
        }

        address miner = state.miner;
        if (miner == address(0)) {
            revert NotMining(tokenId);
        }

        state.active = false;
        state.startedAt = 0;
        state.miner = address(0);

        _lifecycleTransfer = true;
        _transfer(address(this), miner, tokenId);
        _lifecycleTransfer = false;

        emit MiningStopped(tokenId, miner, block.timestamp);
    }

    /// @notice Returns whether a token currently has an active mining session.
    function isMining(uint256 tokenId) external view returns (bool) {
        _requireMinted(tokenId);
        return _miningStates[tokenId].active;
    }

    /// @notice Returns the recorded mining start timestamp for a token.
    function miningStartedAt(uint256 tokenId) external view returns (uint256) {
        _requireMinted(tokenId);
        return _miningStates[tokenId].startedAt;
    }

    /// @notice Returns the recorded miner for a token while active, otherwise zero address.
    function miningOwner(uint256 tokenId) external view returns (address) {
        _requireMinted(tokenId);
        return _miningStates[tokenId].miner;
    }

    /// @notice Returns the token's immutable mining class.
    function miningClass(uint256 tokenId) external view returns (MiningClass) {
        _requireMinted(tokenId);
        return _tokenClass[tokenId];
    }

    /// @notice Returns the power multiplier of the token's mining class.
    function miningPower(uint256 tokenId) external view returns (uint64) {
        _requireMinted(tokenId);
        return _classPower(_tokenClass[tokenId]);
    }

    /// @notice Returns consolidated mining data for vault/engine reads.
    function getMiningPosition(uint256 tokenId) external view returns (MiningPosition memory) {
        _requireMinted(tokenId);
        MiningClass classId = _tokenClass[tokenId];
        MiningState memory state = _miningStates[tokenId];

        return MiningPosition({
            miner: state.miner,
            startedAt: state.startedAt,
            active: state.active,
            classId: classId,
            power: _classPower(classId)
        });
    }

    /// @notice Returns number of minted NFTs for the given class.
    function classMinted(MiningClass classId) external view returns (uint256) {
        return _classMinted[uint8(classId)];
    }

    /// @notice Returns number of minted NFTs for the given distribution phase.
    function phaseMinted(DistributionPhase phase) external view returns (uint256) {
        return _phaseMinted[uint8(phase)];
    }

    /// @notice Returns minted token count.
    function totalMinted() external view returns (uint256) {
        return _nextTokenId;
    }

    /// @notice Returns fixed supply cap for a class.
    function classCap(MiningClass classId) external pure returns (uint256) {
        return _classCap(classId);
    }

    /// @notice Returns fixed mining power for a class.
    function classPower(MiningClass classId) external pure returns (uint256) {
        return _classPower(classId);
    }

    /// @notice Returns fixed phase allocation cap.
    function phaseCap(DistributionPhase phase) external pure returns (uint256) {
        return _phaseCap(phase);
    }

    /// @inheritdoc ERC721
    function approve(address to, uint256 tokenId) public virtual override {
        if (_miningStates[tokenId].active) {
            revert TokenInMining(tokenId);
        }
        super.approve(to, tokenId);
    }

    /// @dev Restricts custody entry/exit transfers to the mining lifecycle flow only.
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);
        bool touchesCustody = to == address(this) || from == address(this);
        if (touchesCustody && !_lifecycleTransfer) {
            revert CustodyTransferNotAllowed();
        }
        return super._update(to, tokenId, auth);
    }

    function _requireMinted(uint256 tokenId) internal view {
        if (_ownerOf(tokenId) == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
    }

    function _classCap(MiningClass classId) internal pure returns (uint32) {
        if (classId == MiningClass.Stone) return 40_000;
        if (classId == MiningClass.Obsidian) return 25_000;
        if (classId == MiningClass.Iron) return 15_000;
        if (classId == MiningClass.Steel) return 10_000;
        if (classId == MiningClass.Titanium) return 6_000;
        if (classId == MiningClass.Diamond) return 3_000;
        if (classId == MiningClass.Mithril) return 1_000;
        revert InvalidMiningClass(uint8(classId));
    }

    function _classPower(MiningClass classId) internal pure returns (uint64) {
        if (classId == MiningClass.Stone) return 1;
        if (classId == MiningClass.Obsidian) return 2;
        if (classId == MiningClass.Iron) return 4;
        if (classId == MiningClass.Steel) return 8;
        if (classId == MiningClass.Titanium) return 16;
        if (classId == MiningClass.Diamond) return 32;
        if (classId == MiningClass.Mithril) return 64;
        revert InvalidMiningClass(uint8(classId));
    }

    function _phaseCap(DistributionPhase phase) internal pure returns (uint32) {
        if (phase == DistributionPhase.Airdrop) return 10_000;
        if (phase == DistributionPhase.EarlyAccess) return 10_000;
        if (phase == DistributionPhase.PublicSale) return 80_000;
        revert InvalidDistributionPhase(uint8(phase));
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
