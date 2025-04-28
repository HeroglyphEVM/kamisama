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

    uint32[] private NATIONS_INPUT;
    uint32[] private QUANTITIES_INPUT;

    KamisamaHarness private underTest;

    function setUp() public {
        vm.mockCall(lzEndpoint, abi.encodeWithSignature("setDelegate(address)"), abi.encode(true));
        underTest = new KamisamaHarness(COST, owner, treasury, lzEndpoint);

        delete NATIONS_INPUT;
        delete QUANTITIES_INPUT;
    }

    function test_constructor() external {
        underTest = new KamisamaHarness(COST, owner, treasury, lzEndpoint);

        assertEq(underTest.COST(), COST);
        assertEq(underTest.MAX_SUPPLY_PER_NATION(), 1000);
        assertEq(underTest.TOTAL_NATIONS(), 7);
        assertEq(underTest.isImmutable(), false);
        assertEq(underTest.treasury(), treasury);
        assertEq(address(underTest.endpoint()), lzEndpoint);
    }

    function test_lzReceive_whenNoMoreFreeMintPass_thenReverts() external {
        underTest.exposed_setFreeMintPassLeft(0);
        Origin memory origin = generateOrigin();
        bytes32 guid = bytes32(abi.encodePacked(address(this), "Random Test"));
        address receiver = generateAddress("Receiver");

        vm.expectRevert(IKamisama.NoMoreFreeMintPass.selector);
        underTest.exposed_lzReceive(origin, guid, abi.encode(99_928, receiver));
    }

    function test_lzReceive_thenGivesFreeMintPass() external {
        uint32 blockNumber = 3_288_827;
        Origin memory origin = generateOrigin();
        bytes32 guid = bytes32(abi.encodePacked(address(this), "Random Test"));
        address receiver = generateAddress("Receiver");
        uint32 expectedPassLeft = underTest.freeMintPassLeft() - 1;

        bytes memory data = abi.encode(blockNumber, receiver);

        expectExactEmit();
        emit IKamisama.FreeMintPassGiven(guid, blockNumber, receiver, expectedPassLeft);

        underTest.exposed_lzReceive(origin, guid, data);

        assertEq(underTest.freeMintPassBalance(receiver), 1);
        assertEq(underTest.freeMintPassLeft(), expectedPassLeft);
    }

    function test_mint_givenMsgValue_whenFreeMintPassIsUsed_thenReverts() external prankAs(user) {
        vm.expectRevert(IKamisama.NativeDetectedWhenFreeMintPassIsUsed.selector);

        underTest.mint{ value: 1 }(NATIONS_INPUT, QUANTITIES_INPUT, true);
    }

    function test_mint_givenMismathArrayLength_thenReverts() external prankAs(user) {
        NATIONS_INPUT.push(0);

        vm.expectRevert(IKamisama.MismathArrayLength.selector);
        underTest.mint(NATIONS_INPUT, QUANTITIES_INPUT, false);
    }

    function test_mint_givenNotExactNativeCost_thenReverts() external prankAs(user) {
        NATIONS_INPUT.push(0);
        QUANTITIES_INPUT.push(1);

        vm.expectRevert(IKamisama.NotEnoughNative.selector);
        underTest.mint{ value: COST - 1 }(NATIONS_INPUT, QUANTITIES_INPUT, false);

        vm.expectRevert(IKamisama.NotEnoughNative.selector);
        underTest.mint{ value: COST + 1 }(NATIONS_INPUT, QUANTITIES_INPUT, false);

        QUANTITIES_INPUT[0] = 2;

        vm.expectRevert(IKamisama.NotEnoughNative.selector);
        underTest.mint{ value: COST }(NATIONS_INPUT, QUANTITIES_INPUT, false);
    }

    function test_mint_whenLastMintedIdIsEqualsOrHigherThanUnlockedIds_thenReverts() external prankAs(user) {
        underTest.exposed_lastMintedID(0, underTest.MAX_SUPPLY_PER_NATION());
        NATIONS_INPUT.push(0);
        QUANTITIES_INPUT.push(1);

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.mint{ value: COST }(NATIONS_INPUT, QUANTITIES_INPUT, false);
    }

    function test_mint_thenMints() external prankAs(user) {
        NATIONS_INPUT.push(0);
        QUANTITIES_INPUT.push(1);

        expectExactEmit();
        emit IKamisama.KamisamaMinted(user, 0, 1);
        underTest.mint{ value: COST }(NATIONS_INPUT, QUANTITIES_INPUT, false);

        assertEq(underTest.lastMintedIdByNation(0), 1);
        assertEq(underTest.ownerOf(1), user);

        assertEq(address(underTest.treasury()).balance, COST);
    }

    function test_mint_givenMultipleMint_thenMints() external pranking {
        changePrank(owner);
        underTest.unlockNewNation();

        uint32 nationOne = 5;
        uint32 nationTwo = 4;

        NATIONS_INPUT.push(0);
        NATIONS_INPUT.push(1);
        QUANTITIES_INPUT.push(nationOne);
        QUANTITIES_INPUT.push(nationTwo);
        uint32 extra = underTest.MAX_SUPPLY_PER_NATION();

        changePrank(user);

        for (uint32 i = 0; i < nationOne; ++i) {
            expectExactEmit();
            emit IKamisama.KamisamaMinted(user, 0, i + 1);
        }

        for (uint32 i = 0; i < nationTwo; ++i) {
            expectExactEmit();
            emit IKamisama.KamisamaMinted(user, 1, extra + i + 1);
        }
        underTest.mint{ value: COST * (nationOne + nationTwo) }(NATIONS_INPUT, QUANTITIES_INPUT, false);

        assertEq(underTest.lastMintedIdByNation(0), nationOne);
        assertEq(underTest.lastMintedIdByNation(1), nationTwo);
        assertEq(treasury.balance, COST * (nationOne + nationTwo));
    }

    function test_executeMint_whenMaxSupplyReached_thenReverts() external prankAs(user) {
        underTest.exposed_lastMintedID(0, underTest.MAX_SUPPLY_PER_NATION());

        NATIONS_INPUT.push(0);
        QUANTITIES_INPUT.push(1);

        vm.expectRevert(IKamisama.MaxSupplyReached.selector);
        underTest.mint{ value: COST }(NATIONS_INPUT, QUANTITIES_INPUT, false);
    }

    function test_executeMint_whenNotExistingNation_thenReverts() external {
        vm.expectRevert(IKamisama.NationNotFound.selector);
        underTest.exposed_executeMint(1, user, 1, false);
    }

    function test_executeMint_whenNoQuantity_thenReverts() external {
        vm.expectRevert(IKamisama.InvalidQuantity.selector);
        underTest.exposed_executeMint(0, user, 0, false);
    }

    function test_executeMint_whenNoFreePass_givenFreePass_thenReverts() external prankAs(user) {
        vm.expectRevert(IKamisama.NoFreePass.selector);
        underTest.exposed_executeMint(0, user, 1, true);

        underTest.exposed_giveFreeMintPass(user, 5);

        vm.expectRevert(IKamisama.NoFreePass.selector);
        underTest.exposed_executeMint(0, user, 6, true);
    }

    function test_executeMint_whenOnlyReservedIDLeft_thenReverts() external prankAs(user) {
        NATIONS_INPUT.push(0);
        QUANTITIES_INPUT.push(underTest.MAX_SUPPLY_PER_NATION() - underTest.RESERVED_IDS_PER_NATION());

        underTest.mint{ value: COST * QUANTITIES_INPUT[0] }(NATIONS_INPUT, QUANTITIES_INPUT, false);

        assertEq(underTest.lastMintedIdByNation(0), QUANTITIES_INPUT[0]);
        assertEq(underTest.ownerOf(QUANTITIES_INPUT[0]), user);

        QUANTITIES_INPUT[0] = 1;

        vm.expectRevert(IKamisama.ValidatorReservedID.selector);
        underTest.mint{ value: COST }(NATIONS_INPUT, QUANTITIES_INPUT, false);
    }

    function test_executeMint_whenFreePass_thenUsesFreePass() external prankAs(user) {
        underTest.exposed_giveFreeMintPass(user, 1);
        underTest.exposed_executeMint(0, user, 1, true);

        assertEq(underTest.freeMintPassBalance(user), 0);
        assertEq(underTest.reservedNFTLeft(0), 14);
    }

    function test_executeMint_whenEverythingMintedWithReserved_thenReflectsMaxSupplyPerNation()
        external
        prankAs(user)
    {
        uint32 reservedAmount = underTest.RESERVED_IDS_PER_NATION();
        uint32 totalAmount = underTest.MAX_SUPPLY_PER_NATION();

        underTest.exposed_giveFreeMintPass(user, reservedAmount);

        underTest.exposed_executeMint(0, user, reservedAmount, true);
        underTest.exposed_executeMint(0, user, totalAmount - reservedAmount, false);

        assertEq(underTest.ownerOf(totalAmount), user);
        assertEq(underTest.reservedNFTLeft(0), 0);
        assertEq(underTest.freeMintPassBalance(user), 0);
    }

    function test_spendFreePass_whenNationHasReachedAllFreePassed_thenReverts() external prankAs(user) {
        uint32 reserved = underTest.RESERVED_IDS_PER_NATION();
        underTest.exposed_giveFreeMintPass(user, reserved);
        underTest.exposed_spendFreePass(0, reserved);

        vm.expectRevert(IKamisama.MaxFreePassUsedOnNation.selector);
        underTest.exposed_spendFreePass(0, 1);
    }

    function test_spendFreePass_whenUserHasNoFreePass_thenReverts() external prankAs(user) {
        vm.expectRevert(IKamisama.NoFreePass.selector);
        underTest.exposed_spendFreePass(0, 1);
    }

    function test_spendFreePass_thenUpdateSystemTracking() external prankAs(user) {
        uint32 reserved = underTest.RESERVED_IDS_PER_NATION();
        uint32 given = 5;
        underTest.exposed_giveFreeMintPass(user, given);

        underTest.exposed_spendFreePass(0, given);

        assertEq(underTest.reservedNFTLeft(0), reserved - given);
        assertEq(underTest.freeMintPassBalance(user), 0);
    }

    function test_fizz_executeMint(uint32 _lastMintedId) external {
        _lastMintedId =
            uint32(bound(_lastMintedId, 1, underTest.MAX_SUPPLY_PER_NATION() - underTest.RESERVED_IDS_PER_NATION()));
        underTest.exposed_lastMintedID(0, _lastMintedId);

        if (_lastMintedId == underTest.MAX_SUPPLY_PER_NATION()) {
            vm.expectRevert(IKamisama.MaxSupplyReached.selector);
            underTest.exposed_executeMint(user);
            return;
        }

        underTest.exposed_executeMint(user);

        assertEq(underTest.lastMintedIdByNation(0), _lastMintedId + 1);
        assertEq(underTest.ownerOf(_lastMintedId + 1), user);
    }

    function test_unlockNewNation_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.unlockNewNation();
    }

    function test_unlockNewNation_whenMaxNationReached_thenReverts() external prankAs(owner) {
        for (uint256 i = 0; i < 6; i++) {
            underTest.unlockNewNation();
        }
        vm.expectRevert(IKamisama.MaxNationReached.selector);
        underTest.unlockNewNation();
    }

    function test_unlockNewNation_whenOwner_thenUnlocks() external prankAs(owner) {
        expectExactEmit();
        emit IKamisama.NewNationUnlocked(1);
        underTest.unlockNewNation();

        assertEq(underTest.lastedUnlockedNation(), 1);
    }

    function test_reveals_whenNotOwner_thenReverts() external prankAs(user) {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        underTest.reveals(1, "ipfs://test");
    }

    function test_reveals_whenImmutable_thenReverts() external prankAs(owner) {
        underTest.setImmutable();
        underTest.reveals(1, "ipfs://test");

        vm.expectRevert(IKamisama.Immutable.selector);
        underTest.reveals(1, "ipfs://test");
    }

    function test_reveals_whenOwner_thenReveals() external prankAs(owner) {
        expectExactEmit();
        emit IKamisama.Revealed(1, "ipfs://test");
        underTest.reveals(1, "ipfs://test");

        assertEq(underTest.nationCollectionURIs(1), "ipfs://test");
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

        underTest.reveals(0, "ipfs://test/");
        assertEq(underTest.tokenURI(1), "ipfs://test/1");
    }

    function test_getNation_thenReturnsCorrectNationId() external view {
        assertEq(underTest.getNation(1), 0);
        assertEq(underTest.getNation(1000), 0);
        assertEq(underTest.getNation(1001), 1);
        assertEq(underTest.getNation(2000), 1);
        assertEq(underTest.getNation(2001), 2);
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

    function exposed_lastMintedID(uint32 _nation, uint32 _lastId) external {
        lastMintedIdByNation[_nation] = _lastId;
    }

    function exposed_setFreeMintPassLeft(uint32 _left) external {
        freeMintPassLeft = _left;
    }

    function exposed_executeMint(address _to) external {
        _executeMint(0, _to, 1, false);
    }

    function exposed_executeMint(uint32 _nation, address _to, uint32 _quantity, bool _useFreePass) external {
        _executeMint(_nation, _to, _quantity, _useFreePass);
    }

    function exposed_giveFreeMintPass(address _to, uint32 _qty) external {
        freeMintPassBalance[_to] += _qty;
    }

    function exposed_spendFreePass(uint32 _nation, uint32 _quantity) external {
        _spendFreePass(_nation, _quantity);
    }
}
