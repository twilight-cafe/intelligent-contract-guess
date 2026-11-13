
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {
    Guess,
    GameStage,
    GameResult
} from "../contracts/main.sol";

contract GuessTest is Test {
    Guess internal game;

    address internal alice = address(0x1);
    address internal bob = address(0x2);
    address internal charlie = address(0x3);
    address internal david = address(0x4);

    uint256 internal constant DURATION = 1 days;

    // =========================================================
    // Setup
    // =========================================================

    function setUp() public {
        game = new Guess();
    }

    function _players2()
        internal
        view
        returns (address[] memory players)
    {
        players = new address[](2);
        players[0] = alice;
        players[1] = bob;
    }

    function _players3()
        internal
        view
        returns (address[] memory players)
    {
        players = new address[](3);
        players[0] = alice;
        players[1] = bob;
        players[2] = charlie;
    }

    function _setup() internal {
        game.setupGame(_players2(), DURATION);
    }

    // =========================================================
    // Commitment
    // =========================================================

    function _hash(
        address player,
        uint256 choice,
        uint256 salt
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                choice,
                salt,
                player,
                game.getGameId()
            )
        );
    }

    function _choose(
    address player,
    uint256 choice,
    uint256 salt
) internal {
    bytes32 commitment = _hash(player, choice, salt);

    vm.prank(player);

    game.choose(commitment);
}

    function _commit(
        address player,
        uint256 choice,
        uint256 salt
    ) internal {
        vm.prank(player);

        game.commit(choice, salt);
    }

    function _start2(
        uint256 a,
        uint256 b
    ) internal {
        _setup();

        _choose(alice, a, 100);
        _choose(bob, b, 200);
    }

    // =========================================================
    // Event assertions
    // =========================================================

    function _assertResult(
        Vm.Log[] memory logs,
        uint256 index,
        address player,
        GameResult result
    ) internal view {
        assertTrue(index < logs.length);

        assertEq(
            logs[index].emitter,
            address(game)
        );

        assertEq(
            logs[index].topics.length,
            3
        );

        assertEq(
            logs[index].topics[0],
            keccak256("Result(address,uint8,uint256)")
        );

        assertEq(
            logs[index].topics[1],
            bytes32(uint256(uint160(player)))
        );

        assertEq(
            logs[index].topics[2],
            bytes32(uint256(result))
        );
    }

    function _assertTwoResults(
        GameResult a,
        GameResult b
    ) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);

        _assertResult(logs, 0, alice, a);
        _assertResult(logs, 1, bob, b);
    }

    // =========================================================
    // 1. Initial state
    // =========================================================

    function testInitialState() public view {
        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Available)
        );

        assertEq(game.getGameId(), 0);
    }

    function testSetupGame() public {
        _setup();

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Gathering)
        );

        assertEq(game.getGameId(), 1);
    }

    function testSetupIncrementsGameId() public {
        _start2(1, 3);

        _commit(alice, 1, 100);

        vm.recordLogs();

        _commit(bob, 3, 200);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);

        game.setupGame(_players2(), DURATION);

        assertEq(game.getGameId(), 2);
    }

    function testRejectsSinglePlayer() public {
        address[] memory players = new address[](1);
        players[0] = alice;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Amount of players must be greater than 1"
            )
        );

        game.setupGame(players, DURATION);
    }

    function testRejectsZeroDeadline() public {
        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Deadline must be greater than 0"
            )
        );

        game.setupGame(_players2(), 0);
    }

    function testRejectsDuplicatePlayers() public {
        address[] memory players = new address[](3);

        players[0] = alice;
        players[1] = bob;
        players[2] = alice;

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Duplicate player"
            )
        );

        game.setupGame(players, DURATION);
    }

    function testRejectsZeroAddress() public {
        address[] memory players = new address[](2);

        players[0] = alice;
        players[1] = address(0);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Invalid player"
            )
        );

        game.setupGame(players, DURATION);
    }

    function testCannotSetupDuringGame() public {
        _setup();

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Game not available"
            )
        );

        game.setupGame(_players2(), DURATION);
    }

    // =========================================================
    // 2. Gathering
    // =========================================================

    function testChooseTransitionsStage() public {
        _setup();

        _choose(alice, 1, 100);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Gathering)
        );

        _choose(bob, 2, 200);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Committing)
        );
    }

    function testRejectsUnauthorizedChoose() public {
        _setup();

        vm.prank(charlie);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Not invited"
            )
        );

        game.choose(bytes32(uint256(1)));
    }

    function testRejectsZeroCommitment() public {
        _setup();

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Can't commit 0 hash"
            )
        );

        game.choose(bytes32(0));
    }

    function testCannotChooseTwice() public {
        _setup();

        _choose(alice, 1, 100);

        bytes32 commitment = _hash(alice, 2, 200);

vm.prank(alice);

vm.expectRevert(
    abi.encodeWithSignature(
        "Error(string)",
        "Your choice has been determined"
    )
);

game.choose(commitment);
    }

    function testCannotChooseAfterGathering() public {
        _start2(1, 3);

        bytes32 commitment = _hash(alice, 2, 300);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Game not gathering"
            )
        );

        game.choose(commitment);
    }

    // =========================================================
    // 3. Commit
    // =========================================================

    function testRejectsUnauthorizedCommit() public {
        _start2(1, 3);

        vm.prank(charlie);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Not invited"
            )
        );

        game.commit(1, 100);
    }

    function testRejectsInvalidChoice() public {
        _start2(1, 3);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Invalid choice"
            )
        );

        game.commit(0, 100);
    }

    function testRejectsChoiceGreaterThanThree() public {
        _start2(1, 3);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Invalid choice"
            )
        );

        game.commit(4, 100);
    }

    function testRejectsWrongSalt() public {
        _start2(1, 3);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Not correct"
            )
        );

        game.commit(1, 999);
    }

    function testRejectsWrongPlayerCommitment() public {
        _start2(1, 3);

        vm.prank(bob);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Not correct"
            )
        );

        game.commit(1, 100);
    }

    function testCannotCommitTwice() public {
        _start2(1, 3);

        _commit(alice, 1, 100);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Your choice has been committed"
            )
        );

        game.commit(1, 100);
    }

    function testCannotCommitBeforeCommitting() public {
        _setup();

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Game not committing"
            )
        );

        game.commit(1, 100);
    }

    // =========================================================
    // 4. Two-player game results
    // =========================================================

    function testRockBeatsScissors() public {
        _start2(1, 3);

        _commit(alice, 1, 100);

        vm.recordLogs();

        _commit(bob, 3, 200);

        _assertTwoResults(
            GameResult.Win,
            GameResult.Lose
        );
    }

    function testPaperBeatsRock() public {
        _start2(2, 1);

        _commit(alice, 2, 100);

        vm.recordLogs();

        _commit(bob, 1, 200);

        _assertTwoResults(
            GameResult.Win,
            GameResult.Lose
        );
    }

    function testScissorsBeatsPaper() public {
        _start2(3, 2);

        _commit(alice, 3, 100);

        vm.recordLogs();

        _commit(bob, 2, 200);

        _assertTwoResults(
            GameResult.Win,
            GameResult.Lose
        );
    }

    function testRockDrawsRock() public {
        _start2(1, 1);

        _commit(alice, 1, 100);

        vm.recordLogs();

        _commit(bob, 1, 200);

        _assertTwoResults(
            GameResult.Equal,
            GameResult.Equal
        );
    }

    function testPaperDrawsPaper() public {
        _start2(2, 2);

        _commit(alice, 2, 100);

        vm.recordLogs();

        _commit(bob, 2, 200);

        _assertTwoResults(
            GameResult.Equal,
            GameResult.Equal
        );
    }

    function testScissorsDrawsScissors() public {
        _start2(3, 3);

        _commit(alice, 3, 100);

        vm.recordLogs();

        _commit(bob, 3, 200);

        _assertTwoResults(
            GameResult.Equal,
            GameResult.Equal
        );
    }

    // =========================================================
    // 5. Fuzz testing
    // =========================================================

    function testFuzzTwoPlayerResults(
        uint256 a,
        uint256 b
    ) public {
        a = bound(a, 1, 3);
        b = bound(b, 1, 3);

        _start2(a, b);

        _commit(alice, a, 100);

        vm.recordLogs();

        _commit(bob, b, 200);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);

        GameResult expectedA;
        GameResult expectedB;

        if (a == b) {
            expectedA = GameResult.Equal;
            expectedB = GameResult.Equal;
        } else if (
            (a == 1 && b == 3) ||
            (a == 2 && b == 1) ||
            (a == 3 && b == 2)
        ) {
            expectedA = GameResult.Win;
            expectedB = GameResult.Lose;
        } else {
            expectedA = GameResult.Lose;
            expectedB = GameResult.Win;
        }

        _assertResult(logs, 0, alice, expectedA);
        _assertResult(logs, 1, bob, expectedB);
    }

    // =========================================================
    // 6. Multi-player
    // =========================================================

    function testThreeDifferentChoicesDraw() public {
        game.setupGame(_players3(), DURATION);

        _choose(alice, 1, 100);
        _choose(bob, 2, 200);
        _choose(charlie, 3, 300);

        _commit(alice, 1, 100);
        _commit(bob, 2, 200);

        vm.recordLogs();

        _commit(charlie, 3, 300);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3);

        _assertResult(logs, 0, alice, GameResult.Equal);
        _assertResult(logs, 1, bob, GameResult.Equal);
        _assertResult(logs, 2, charlie, GameResult.Equal);
    }

    function testOneRevealerOthersLose() public {
        game.setupGame(_players3(), DURATION);

        _choose(alice, 1, 100);
        _choose(bob, 2, 200);
        _choose(charlie, 3, 300);

        _commit(alice, 1, 100);

        vm.warp(block.timestamp + DURATION);

        vm.recordLogs();

        game.checkDDL();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3);

        _assertResult(logs, 0, alice, GameResult.Equal);
        _assertResult(logs, 1, bob, GameResult.Lose);
        _assertResult(logs, 2, charlie, GameResult.Lose);
    }

    function testNoOneReveals() public {
        _start2(1, 3);

        vm.warp(block.timestamp + DURATION);

        vm.recordLogs();

        game.checkDDL();

        _assertTwoResults(
            GameResult.Lose,
            GameResult.Lose
        );
    }

    function testTwoRevealOneTimeout() public {
        game.setupGame(_players3(), DURATION);

        _choose(alice, 1, 100);
        _choose(bob, 2, 200);
        _choose(charlie, 3, 300);

        _commit(alice, 1, 100);
        _commit(bob, 2, 200);

        vm.warp(block.timestamp + DURATION);

        vm.recordLogs();

        game.checkDDL();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 3);

        _assertResult(logs, 0, alice, GameResult.Lose);
        _assertResult(logs, 1, bob, GameResult.Win);
        _assertResult(logs, 2, charlie, GameResult.Lose);
    }

    // =========================================================
    // 7. Deadline
    // =========================================================

    function testDeadlineInclusive() public {
        _start2(1, 3);

        vm.warp(block.timestamp + DURATION);

        vm.recordLogs();

        game.checkDDL();

        _assertTwoResults(
            GameResult.Lose,
            GameResult.Lose
        );
    }

    function testCannotCheckDeadlineBeforeCommitting() public {
        _setup();

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Game not committing"
            )
        );

        game.checkDDL();
    }

    function testCannotCheckDeadlineBeforeExpiry() public {
        _start2(1, 3);

        vm.warp(block.timestamp + DURATION - 1);

        game.checkDDL();

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Committing)
        );
    }

    // =========================================================
    // 8. Game reset
    // =========================================================

    function testCanStartNextGame() public {
        _start2(1, 3);

        _commit(alice, 1, 100);

        vm.recordLogs();

        _commit(bob, 3, 200);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 2);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Available)
        );

        game.setupGame(_players2(), DURATION);

        assertEq(game.getGameId(), 2);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Gathering)
        );
    }

    function testNewGameDoesNotReuseOldCommitment() public {
        _start2(1, 3);

        bytes32 oldHash = _hash(alice, 1, 100);

        _commit(alice, 1, 100);

        vm.recordLogs();

        _commit(bob, 3, 200);

        game.setupGame(_players2(), DURATION);

        assertEq(game.getGameId(), 2);

        vm.prank(alice);

        game.choose(oldHash);

        _choose(bob, 3, 200);

        vm.prank(alice);

        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "Not correct"
            )
        );

        game.commit(1, 100);
    }

    // =========================================================
    // 9. Independent instances
    // =========================================================

    function testIndependentInstances() public {
        Guess anotherGame = new Guess();

        game.setupGame(_players2(), DURATION);

        address[] memory players = new address[](2);
        players[0] = charlie;
        players[1] = david;

        anotherGame.setupGame(players, DURATION);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Gathering)
        );

        assertEq(
            uint256(anotherGame.getStage()),
            uint256(GameStage.Gathering)
        );

        assertEq(game.getGameId(), 1);
        assertEq(anotherGame.getGameId(), 1);

        _choose(alice, 1, 100);

        bytes32 commitment = keccak256(
    abi.encode(
        uint256(3),
        uint256(300),
        charlie,
        anotherGame.getGameId()
    )
);

vm.prank(charlie);

anotherGame.choose(commitment);

        assertEq(
            uint256(game.getStage()),
            uint256(GameStage.Gathering)
        );

        assertEq(
            uint256(anotherGame.getStage()),
            uint256(GameStage.Gathering)
        );
    }
}
