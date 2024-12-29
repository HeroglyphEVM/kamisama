// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../base/BaseTest.t.sol";
import { Kamisama, IKamisama } from "src/Kamisama.sol";
import { Origin } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract KamisamaTest is BaseTest {
    uint256 internal constant COST = 0.25 ether;

    address private owner = generateAddress("Owner");
    address private user = generateAddress("User", 10_000e18);
    address private treasury = generateAddress("Treasury");
    address private lzEndpoint = generateAddress("LzEndpoint");

    KamisamaHarness private underTest;

    function setUp() public {
        vm.mockCall(lzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));
        underTest = new KamisamaHarness(COST, owner, treasury, lzEndpoint);
    }

    function test_constructor() external {
        underTest = new KamisamaHarness(COST, owner, treasury, lzEndpoint);

        assertEq(underTest.COST(), COST);
        assertEq(underTest.MAX_SUPPLY(), 7000);
        assertEq(underTest.unlockedIds(), 1000);
        assertEq(underTest.lastMintedID(), 0);
        assertEq(underTest.isImmutable(), false);
        assertEq(underTest.treasury(), treasury);
        assertEq(address(underTest.endpoint()), lzEndpoint);
    }

    function test_lzReceive_whenMaxSupplyReached() external {
        underTest.exposed_lastMintedID(underTest.unlockedIds());

        Origin memory origin = generateOrigin();
        bytes32 guid = bytes32(abi.encodePacked(address(this), "Random Test"));
        address receiver = generateAddress("Receiver");

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.exposed_lzReceive(origin, guid, abi.encode(99_928, receiver));
    }

    function test_lzReceive_thenMints() external {
        uint32 blockNumber = 3_288_827;
        Origin memory origin = generateOrigin();
        bytes32 guid = bytes32(abi.encodePacked(address(this), "Random Test"));
        address receiver = generateAddress("Receiver");

        bytes memory data = abi.encode(blockNumber, receiver);

        expectExactEmit();
        emit IKamisama.KamisamaValidatorMinted(1, receiver, guid, blockNumber);

        underTest.exposed_lzReceive(origin, guid, data);

        assertEq(underTest.lastMintedID(), 1);
        assertEq(underTest.ownerOf(1), receiver);
    }

    function test_mint_givenNotExactNativeCost_thenReverts() external prankAs(user) {
        vm.expectRevert(IKamisama.NotEnoughNative.selector);
        underTest.mint{ value: COST - 1 }();

        vm.expectRevert(IKamisama.NotEnoughNative.selector);
        underTest.mint{ value: COST + 1 }();
    }

    function test_mint_whenLastMintedIdIsEqualsOrHigherThanUnlockedIds_thenReverts() external prankAs(user) {
        underTest.exposed_lastMintedID(underTest.unlockedIds());

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.mint{ value: COST }();
    }

    function test_mint_thenMints() external prankAs(user) {
        expectExactEmit();
        emit IKamisama.KamisamaMinted(user, 1, COST);
        underTest.mint{ value: COST }();

        assertEq(underTest.lastMintedID(), 1);
        assertEq(underTest.ownerOf(1), user);

        assertEq(address(underTest.treasury()).balance, COST);
    }

    function test_executeMint_whenNextIdIsHigherThanUnlockedIds_thenReverts() external {
        underTest.exposed_lastMintedID(underTest.unlockedIds());

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.exposed_executeMint(user);
    }

    function test_exectueMint_whenMintEveryting_thenStopsAtTheUnlockedIds() external {
        uint256 to = underTest.MAX_SUPPLY();
        uint256 unlockedIds = underTest.unlockedIds();

        for (uint256 i = 0; i < to; i++) {
            if (i + 1 > unlockedIds) {
                vm.expectRevert(IKamisama.MaxSupplyReached.selector);
                underTest.exposed_executeMint(user);
                continue;
            }

            expectExactEmit();
            emit IKamisama.KamisamaMinted(user, i + 1, 0);
            underTest.exposed_executeMint(user);

            assertEq(underTest.lastMintedID(), i + 1);
            assertEq(underTest.ownerOf(i + 1), user);
        }
    }

    function test_executeMint_whenMintEveryting_givenHigherIds_thenStopsAtTheUnlockedIds() external pranking {
        changePrank(owner);
        underTest.injectMore(1250);
        uint256 unlockedIds = underTest.unlockedIds();
        uint256 to = underTest.MAX_SUPPLY();

        changePrank(user);

        for (uint256 i = 0; i < to; i++) {
            if (i + 1 > unlockedIds) {
                vm.expectRevert(IKamisama.MaxSupplyReached.selector);
                underTest.exposed_executeMint(user);
                continue;
            }

            underTest.exposed_executeMint(user);

            assertEq(underTest.lastMintedID(), i + 1);
            assertEq(underTest.ownerOf(i + 1), user);
        }

        assertEq(underTest.ownerOf(unlockedIds), user);
    }

    function test_executeMint_whenFullyUnlocked_thenMintsEverything() external pranking {
        uint256 to = underTest.MAX_SUPPLY();

        changePrank(owner);
        underTest.injectMore(uint32(to - underTest.unlockedIds()));

        changePrank(user);

        for (uint256 i = 0; i < to; i++) {
            underTest.exposed_executeMint(user);

            assertEq(underTest.lastMintedID(), i + 1);
            assertEq(underTest.ownerOf(i + 1), user);
        }

        assertEq(underTest.ownerOf(to), user);

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.exposed_executeMint(user);
    }

    function test_fizz_executeMint(uint32 _lastMintedId) external {
        _lastMintedId = uint32(bound(_lastMintedId, 1, underTest.MAX_SUPPLY()));
        underTest.exposed_lastMintedID(_lastMintedId);

        uint256 unlockedIds = underTest.unlockedIds();

        if (_lastMintedId >= unlockedIds) {
            vm.expectRevert(IKamisama.MaxSupplyReached.selector);
            underTest.exposed_executeMint(user);
            return;
        }

        underTest.exposed_executeMint(user);

        assertEq(underTest.lastMintedID(), _lastMintedId + 1);
        assertEq(underTest.ownerOf(_lastMintedId + 1), user);
    }

    function test_injectMore_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.injectMore(1000);
    }

    function test_injectMore_whenMaxSupplyReached_thenReverts() external prankAs(owner) {
        uint256 settingTo = underTest.MAX_SUPPLY() - underTest.unlockedIds() + 1;

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.injectMore(uint32(settingTo));
    }

    function test_injectMore_whenOwner_thenInjects() external prankAs(owner) {
        uint32 unlockedIdsBefore = underTest.unlockedIds();
        uint32 adding = 256;

        expectExactEmit();
        emit IKamisama.MoreUnlocked(adding);
        underTest.injectMore(adding);

        assertEq(underTest.unlockedIds(), unlockedIdsBefore + adding);
    }

    function test_reveals_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.reveals("ipfs://test");
    }

    function test_reveals_whenImmutable_thenReverts() external prankAs(owner) {
        underTest.setImmutable();

        vm.expectRevert(IKamisama.Immutable.selector);
        underTest.reveals("ipfs://test");
    }

    function test_reveals_whenOwner_thenReveals() external prankAs(owner) {
        expectExactEmit();
        emit IKamisama.Revealed("ipfs://test");
        underTest.reveals("ipfs://test");

        assertEq(underTest.collectionURI(), "ipfs://test");
    }

    function test_setImmutable_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.setImmutable();
    }

    function test_setImmutable_whenImmutable_thenReverts() external prankAs(owner) {
        expectExactEmit();
        emit IKamisama.ImmutableActivated();
        underTest.setImmutable();

        assertTrue(underTest.isImmutable());
    }

    function test_setTreasury_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.setTreasury(treasury);
    }

    function test_setTreasury_whenInvalidTreasury_thenReverts() external prankAs(owner) {
        vm.expectRevert(IKamisama.InvalidTreasury.selector);
        underTest.setTreasury(address(0));
    }

    function test_setTreasury_whenOwner_thenSets() external prankAs(owner) {
        expectExactEmit();
        emit IKamisama.TreasurySet(treasury);
        underTest.setTreasury(treasury);

        assertEq(underTest.treasury(), treasury);
    }

    function test_tokenURI_whenRevealed_thenReturnsCorrectURL() external prankAs(owner) {
        underTest.exposed_executeMint(user);

        underTest.reveals("ipfs://test/");
        assertEq(underTest.tokenURI(1), "ipfs://test/1");
    }

    function generateOrigin() private view returns (Origin memory) {
        return Origin({ srcEid: 1, sender: bytes32(abi.encode(address(this))), nonce: 1 });
    }
}

contract KamisamaHarness is Kamisama {
    uint256 private ID = 1;

    constructor(uint256 _cost, address _owner, address _treasury, address _lzEndpoint)
        Kamisama(_cost, _owner, _treasury, _lzEndpoint)
    { }

    function exposed_lzReceive(Origin calldata _origin, bytes32 _guid, bytes calldata _data) external {
        _lzReceive(_origin, _guid, _data, address(0), _data);
    }

    function exposed_lastMintedID(uint32 _lastId) external {
        lastMintedID = _lastId;
    }

    function exposed_executeMint(address _to) external {
        _executeMint(_to);
    }
}
