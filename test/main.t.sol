pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Guess, GameStage, GameResult} from "../contracts/main.sol";

contract GuessTest is Test {
    Guess guess;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    event Result(address indexed player, GameResult indexed result);

    function setUp() public {
        guess = new Guess();
    }

    function _hash(
        uint256 choice,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(choice, salt));
    }

    function _setup() internal {
        address[2] memory players = [alice, bob];
        guess.setupGame(players);
    }

    function _chooseBoth(
        uint256 ac,
        uint256 bc,
        uint256 xas,
        uint256 bs
    ) internal {
        vm.prank(alice);
        guess.choose(_hash(ac, xas));
        vm.prank(bob);
        guess.choose(_hash(bc, bs));
    }

    function _assertStage(GameStage expected) internal view {
        assertEq(uint256(guess.getStage()), uint256(expected));
    }

    function test_SetupGame_EntersGathering() public {
        _setup();
        _assertStage(GameStage.Gathering);
    }

    function test_ChooseBoth_EntersCommitting() public {
        _setup();

        vm.prank(alice);
        guess.choose(_hash(1, 11));
        _assertStage(GameStage.Gathering);

        vm.prank(bob);
        guess.choose(_hash(2, 22));
        _assertStage(GameStage.Committing);
    }

    function test_FirstCommit_StaysCommitting_SecondCommit_Settles() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        guess.commit(1, 11);
        _assertStage(GameStage.Committing);

        vm.expectEmit(true, true, false, true);
        emit Result(alice, GameResult.Lose);
        vm.expectEmit(true, true, false, true);
        emit Result(bob, GameResult.Win);

        vm.prank(bob);
        guess.commit(2, 22);

        _assertStage(GameStage.Available);
    }

    function test_EqualChoice() public {
        _setup();
        _chooseBoth(2, 2, 11, 22);

        vm.prank(alice);
        guess.commit(2, 11);

        vm.expectEmit(true, true, false, true);
        emit Result(alice, GameResult.Equal);
        vm.expectEmit(true, true, false, true);
        emit Result(bob, GameResult.Equal);

        vm.prank(bob);
        guess.commit(2, 22);
    }

    function test_ThreeBeatsTwo_Player0Wins() public {
        _setup();
        _chooseBoth(3, 2, 11, 22);

        vm.prank(alice);
        guess.commit(3, 11);

        vm.expectEmit(true, true, false, true);
        emit Result(alice, GameResult.Win);
        vm.expectEmit(true, true, false, true);
        emit Result(bob, GameResult.Lose);

        vm.prank(bob);
        guess.commit(2, 22);
    }

    function test_TwoBeatsOne_Player1Wins() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        guess.commit(1, 11);

        vm.expectEmit(true, true, false, true);
        emit Result(alice, GameResult.Lose);
        vm.expectEmit(true, true, false, true);
        emit Result(bob, GameResult.Win);

        vm.prank(bob);
        guess.commit(2, 22);
    }

    function test_Revert_InvalidChoice() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        vm.expectRevert(bytes("Invalid choice"));
        guess.commit(4, 11);
    }

    function test_Revert_HashMismatch() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        vm.expectRevert(bytes("Not correct"));
        guess.commit(1, 12);
    }

    function test_Revert_NotInvited() public {
        _setup();

        vm.prank(carol);
        vm.expectRevert(bytes("Not invited"));
        guess.choose(_hash(1, 1));

        _chooseBoth(1, 2, 11, 22);

        vm.prank(carol);
        vm.expectRevert(bytes("Not invited"));
        guess.commit(1, 1);
    }

    function test_Revert_StageMismatch() public {
        _setup();

        vm.prank(alice);
        vm.expectRevert(bytes("Game not committing"));
        guess.commit(1, 1);

        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        vm.expectRevert(bytes("Game not gathering"));
        guess.choose(_hash(1, 1));
    }

    function test_Revert_SetupGameWhenNotAvailable() public {
        _setup();

        address[2] memory players = [alice, bob];
        vm.expectRevert(bytes("Game not available"));
        guess.setupGame(players);
    }

    function test_CheckDDL_BeforeDeadline_NoSettle() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        guess.commit(1, 11);

        guess.checkDDL();
        _assertStage(GameStage.Committing);
    }

    function test_CheckDDL_AfterDeadline_SettlesMissingCommitAsLose() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        guess.commit(1, 11);

        vm.warp(block.timestamp + 2 days + 1);

        vm.expectEmit(true, true, false, true);
        emit Result(alice, GameResult.Win);
        vm.expectEmit(true, true, false, true);
        emit Result(bob, GameResult.Lose);

        guess.checkDDL();
        _assertStage(GameStage.Available);
    }

    function test_Revert_CheckDDL_NotCommitting() public {
        vm.expectRevert(bytes("Game not committing"));
        guess.checkDDL();
    }

    function test_Restart_AfterSettlement() public {
        _setup();
        _chooseBoth(1, 2, 11, 22);

        vm.prank(alice);
        guess.commit(1, 11);
        vm.prank(bob);
        guess.commit(2, 22);

        address[2] memory players = [bob, carol];
        guess.setupGame(players);
        _assertStage(GameStage.Gathering);
    }

    function test_DuplicateChoose_AdvancesCount() public {
        _setup();

        vm.prank(alice);
        guess.choose(_hash(1, 11));
        vm.prank(alice);
        guess.choose(_hash(2, 22));

        _assertStage(GameStage.Committing);
    }
}
