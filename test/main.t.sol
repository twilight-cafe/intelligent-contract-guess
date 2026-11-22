// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Guess, GameStage, GameResult} from "../contracts/main.sol";

/// @notice Guess 非资金部分测试套件
/// 覆盖:setup 校验 / choose / commit / 哈希绑定 / 判定逻辑(穷举+模糊) /
///       DDL 边界 / 阶段机 / 房间隔离 / 事件完整性 / 历史 bug 回归
/// 不覆盖:资金分配(未接入);Busy 锁(合约无外部调用,无法从外部触发重入)
contract GuessTest is Test {
    Guess internal guess;

    address internal constant FOUNDER = address(0xF00D); // 不在玩家列表里
    address internal constant STRANGER = address(0xBEEF);
    uint256 internal constant T0 = 1_000_000;
    uint256 internal constant DDL_LEN = 100;

    // 与合约一致,用于 expectEmit
    event Result(address indexed player, GameResult indexed result, uint256 gameId);

    function setUp() public {
        vm.warp(T0);
        guess = new Guess();
    }

    // ================================================================
    //                          工具函数
    // ================================================================

    function _players(uint256 n) internal pure returns (address[] memory ps) {
        ps = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            ps[i] = address(uint160(0x10000 + i));
        }
    }

    function _salt(uint256 roomId, uint256 idx) internal pure returns (bytes32) {
        return keccak256(abi.encode("SALT", roomId, idx));
    }

    // 必须与合约 commit 的原像布局完全一致
    function _hash(uint256 choice, bytes32 salt, address player, uint256 roomId)
        internal pure returns (bytes32)
    {
        return keccak256(abi.encode(choice, salt, player, roomId));
    }

    function _setup(address[] memory ps) internal returns (uint256) {
        vm.prank(FOUNDER);
        return guess.setupGame(ps, DDL_LEN);
    }

    // choices[i]==0 表示该玩家弃局:Gathering 阶段仍须交 hash(用 choice=1 占位),之后不揭示
    function _chooseAll(uint256 roomId, address[] memory ps, uint256[] memory choices) internal {
        for (uint256 i = 0; i < ps.length; ++i) {
            uint256 c = choices[i] == 0 ? 1 : choices[i];
            vm.prank(ps[i]);
            guess.choose(roomId, _hash(c, _salt(roomId, i), ps[i], roomId));
        }
    }

    // 进入 Committing:所有人交 choice=1 的 hash
    function _roomCommitting(uint256 n) internal returns (uint256 id, address[] memory ps) {
        ps = _players(n);
        id = _setup(ps);
        uint256[] memory cs = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) cs[i] = 1;
        _chooseAll(id, ps, cs);
    }

    // 结算前挂好全部事件断言:数量 = n、顺序 = 玩家顺序、三个字段全查
    function _expectResults(address[] memory ps, GameResult[] memory exp, uint256 roomId) internal {
        for (uint256 i = 0; i < ps.length; ++i) {
            vm.expectEmit(true, true, true, true, address(guess));
            emit Result(ps[i], exp[i], roomId);
        }
    }

    /// @notice 独立参考判定(不复制合约的 ch1/ch2 推导),已与合约逻辑穷举交叉验证
    /// 规则:1克3、2克1、3克2;无人揭示→全员Equal;有人弃局→揭示者Equal/弃局者Lose;
    ///       全揭示且1或3种手势→Equal;全揭示且2种手势→胜者Win/败者Lose
    function _expected(uint256[] memory choices) internal pure returns (GameResult[] memory exp) {
        uint256 n = choices.length;
        exp = new GameResult[](n);
        bool[4] memory present;
        uint256 revealed;
        for (uint256 i = 0; i < n; ++i) {
            if (choices[i] != 0) {
                present[choices[i]] = true;
                ++revealed;
            }
        }
        uint256 distinct = (present[1] ? 1 : 0) + (present[2] ? 1 : 0) + (present[3] ? 1 : 0);
        if (distinct == 0) {
            for (uint256 i = 0; i < n; ++i) exp[i] = GameResult.Equal;
            return exp;
        }
        if (revealed != n || distinct == 1 || distinct == 3) {
            for (uint256 i = 0; i < n; ++i) {
                exp[i] = choices[i] == 0 ? GameResult.Lose : GameResult.Equal;
            }
            return exp;
        }
        uint256 a;
        uint256 b;
        for (uint256 c = 1; c <= 3; ++c) {
            if (present[c]) {
                if (a == 0) a = c;
                else b = c;
            }
        }
        uint256 winner = (a == b % 3 + 1) ? a : b; // a 克 b 当且仅当 a == b%3+1
        for (uint256 i = 0; i < n; ++i) {
            exp[i] = choices[i] == winner ? GameResult.Win : GameResult.Lose;
        }
    }

    function _runGame(uint256[] memory choices)
        internal returns (uint256 roomId, address[] memory ps)
    {
        return _runGameExpect(choices, _expected(choices));
    }

    // 完整跑一局并断言结果事件 + 终态 Locked
    function _runGameExpect(uint256[] memory choices, GameResult[] memory exp)
        internal returns (uint256 roomId, address[] memory ps)
    {
        ps = _players(choices.length);
        roomId = _setup(ps);
        _chooseAll(roomId, ps, choices);

        uint256 revealCount;
        for (uint256 i = 0; i < choices.length; ++i) {
            if (choices[i] != 0) ++revealCount;
        }

        uint256 done;
        for (uint256 i = 0; i < choices.length; ++i) {
            if (choices[i] == 0) continue;
            ++done;
            if (done == revealCount && revealCount == choices.length) {
                _expectResults(ps, exp, roomId); // 最后一笔 commit 触发结算
            }
            vm.prank(ps[i]);
            guess.commit(roomId, choices[i], _salt(roomId, i));
        }
        if (revealCount < choices.length) {
            vm.warp(block.timestamp + DDL_LEN + 1);
            _expectResults(ps, exp, roomId);
            guess.checkDDL(roomId);
        }
        assertEq(uint8(guess.getStage(roomId)), uint8(GameStage.Locked), "must settle to Locked");
    }

    // ================================================================
    //                        setupGame
    // ================================================================

    function test_setup_sequentialIds_initialStage() public {
        for (uint256 k = 0; k < 3; ++k) {
            uint256 id = _setup(_players(2));
            assertEq(id, k, "room id must be sequential");
            assertEq(uint8(guess.getStage(id)), uint8(GameStage.Gathering));
        }
    }

    function test_setup_reverts_tooFewPlayers() public {
        vm.expectRevert("Amount of players must be greater than 1");
        guess.setupGame(new address[](0), DDL_LEN);
        vm.expectRevert("Amount of players must be greater than 1");
        guess.setupGame(_players(1), DDL_LEN);
    }

    function test_setup_reverts_zeroDDLLen() public {
        vm.expectRevert("Deadline must be greater than 0");
        guess.setupGame(_players(2), 0);
    }

    function test_setup_reverts_zeroAddress() public {
        address[] memory ps = _players(3);
        ps[1] = address(0);
        vm.expectRevert("Invalid player");
        guess.setupGame(ps, DDL_LEN);
    }

    function test_setup_reverts_duplicatePlayers() public {
        address[] memory ps = _players(3);
        ps[2] = ps[0]; // 非相邻重复
        vm.expectRevert("Duplicate player");
        guess.setupGame(ps, DDL_LEN);

        address[] memory ps2 = _players(2);
        ps2[1] = ps2[0]; // 相邻重复
        vm.expectRevert("Duplicate player");
        guess.setupGame(ps2, DDL_LEN);
    }

    function test_setup_creatorNeedNotBePlayer() public {
        uint256 id = _setup(_players(2)); // FOUNDER 不在列表中,任何人可建房
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Gathering));
    }

    // ================================================================
    //                          choose
    // ================================================================

    function test_choose_stageTransitionsOnlyAfterAll() public {
        address[] memory ps = _players(3);
        uint256 id = _setup(ps);
        for (uint256 i = 0; i < 2; ++i) {
            vm.prank(ps[i]);
            guess.choose(id, _hash(1, _salt(id, i), ps[i], id));
            assertEq(uint8(guess.getStage(id)), uint8(GameStage.Gathering));
        }
        vm.prank(ps[2]);
        guess.choose(id, _hash(1, _salt(id, 2), ps[2], id));
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Committing));
    }

    function test_choose_reverts_notInvited() public {
        uint256 id = _setup(_players(2));
        vm.prank(STRANGER);
        vm.expectRevert("Not invited");
        guess.choose(id, bytes32(uint256(1)));
    }

    function test_choose_reverts_doubleChoose() public {
        address[] memory ps = _players(3);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        guess.choose(id, _hash(1, _salt(id, 0), ps[0], id));
        vm.prank(ps[0]);
        vm.expectRevert("Your choice has been determined");
        guess.choose(id, _hash(2, _salt(id, 0), ps[0], id));
    }

    function test_choose_reverts_zeroHash() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        vm.expectRevert("Can't commit 0 hash");
        guess.choose(id, bytes32(0));
    }

    function test_choose_reverts_inCommitting() public {
        (uint256 id, address[] memory ps) = _roomCommitting(2);
        vm.prank(ps[0]);
        vm.expectRevert("Game not gathering");
        guess.choose(id, bytes32(uint256(1)));
    }

    function test_choose_reverts_invalidRoom() public {
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x32));
        guess.choose(999, bytes32(uint256(1)));
    }

    function testFuzz_choose_anyNonZeroHashAccepted(bytes32 h) public {
        vm.assume(h != 0);
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        guess.choose(id, h); // choose 无法校验原像,任意非零 hash 都合法
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Gathering));
    }

    // ================================================================
    //                          commit
    // ================================================================

    function test_commit_reverts_inGathering() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        vm.expectRevert("Game not committing");
        guess.commit(id, 1, _salt(id, 0));
    }

    function test_commit_reverts_notInvited() public {
        (uint256 id,) = _roomCommitting(2);
        vm.prank(STRANGER);
        vm.expectRevert("Not invited");
        guess.commit(id, 1, _salt(id, 0));
    }

    function test_commit_reverts_invalidChoice() public {
        (uint256 id, address[] memory ps) = _roomCommitting(2);
        vm.prank(ps[0]);
        vm.expectRevert("Invalid choice");
        guess.commit(id, 0, _salt(id, 0));
        vm.prank(ps[0]);
        vm.expectRevert("Invalid choice");
        guess.commit(id, 4, _salt(id, 0));
    }

    function testFuzz_commit_reverts_invalidChoice(uint256 c) public {
        vm.assume(c != 1 && c != 2 && c != 3);
        (uint256 id, address[] memory ps) = _roomCommitting(2);
        vm.prank(ps[0]);
        vm.expectRevert("Invalid choice");
        guess.commit(id, c, _salt(id, 0));
    }

    function test_commit_reverts_doubleCommit() public {
        (uint256 id, address[] memory ps) = _roomCommitting(3); // 3人局,首次commit后仍在Committing
        vm.prank(ps[0]);
        guess.commit(id, 1, _salt(id, 0));
        vm.prank(ps[0]);
        vm.expectRevert("Your choice has been committed");
        guess.commit(id, 1, _salt(id, 0));
    }

    function test_commit_reverts_wrongChoice() public {
        (uint256 id, address[] memory ps) = _roomCommitting(2);
        vm.prank(ps[0]);
        vm.expectRevert("Not correct");
        guess.commit(id, 2, _salt(id, 0)); // hash 是 choice=1 的
    }

    function testFuzz_commit_reverts_wrongSalt(bytes32 wrong) public {
        (uint256 id, address[] memory ps) = _roomCommitting(2);
        vm.assume(wrong != _salt(id, 0));
        vm.prank(ps[0]);
        vm.expectRevert("Not correct");
        guess.commit(id, 1, wrong);
    }

    // 哈希绑定 msg.sender:抄别人的 hash 无法用对应原像揭示
    function test_commit_reverts_crossPlayerReplay() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        bytes32 S = bytes32("S");
        bytes32 h0 = _hash(1, S, ps[0], id);
        vm.prank(ps[0]);
        guess.choose(id, h0);
        vm.prank(ps[1]);
        guess.choose(id, h0); // ps[1] 抄 ps[0] 的 hash
        vm.prank(ps[1]);
        vm.expectRevert("Not correct");
        guess.commit(id, 1, S);
    }

    // 哈希绑定 roomId:同 choice+salt+玩家,跨房复用失败;本房正常作对照
    function test_commit_reverts_crossRoomReplay() public {
        address[] memory ps = _players(2);
        uint256 id0 = _setup(ps);
        uint256 id1 = _setup(ps);
        bytes32 S = bytes32("S");
        bytes32 h0 = _hash(1, S, ps[0], id0);

        vm.prank(ps[0]);
        guess.choose(id0, h0);
        vm.prank(ps[1]);
        guess.choose(id0, _hash(1, S, ps[1], id0));
        vm.prank(ps[0]);
        guess.choose(id1, h0); // 跨房复用
        vm.prank(ps[1]);
        guess.choose(id1, _hash(1, S, ps[1], id1));

        vm.prank(ps[0]);
        vm.expectRevert("Not correct");
        guess.commit(id1, 1, S);

        vm.prank(ps[0]);
        guess.commit(id0, 1, S); // 对照:同一原像在 id0 成功
        assertEq(uint8(guess.getStage(id0)), uint8(GameStage.Committing));
    }

    // 边界:交的是 choice=4 的 hash → 永远无法揭示 → 超时判负,其余人 Equal
    function test_commit_hashOfInvalidChoice_timeoutLose() public {
        address[] memory ps = _players(3);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        guess.choose(id, _hash(4, _salt(id, 0), ps[0], id));
        vm.prank(ps[1]);
        guess.choose(id, _hash(1, _salt(id, 1), ps[1], id));
        vm.prank(ps[2]);
        guess.choose(id, _hash(2, _salt(id, 2), ps[2], id));

        vm.prank(ps[0]);
        vm.expectRevert("Invalid choice");
        guess.commit(id, 4, _salt(id, 0));
        vm.prank(ps[1]);
        guess.commit(id, 1, _salt(id, 1));
        vm.prank(ps[2]);
        guess.commit(id, 2, _salt(id, 2));
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Committing)); // 2/3,未结算

        vm.warp(block.timestamp + DDL_LEN + 1);
        GameResult[] memory exp = new GameResult[](3);
        exp[0] = GameResult.Lose;
        exp[1] = GameResult.Equal;
        exp[2] = GameResult.Equal;
        _expectResults(ps, exp, id);
        guess.checkDDL(id);
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Locked));
    }

    // ================================================================
    //                    判定逻辑:回归 + 穷举 + 模糊
    // ================================================================

    // 回归:曾出现"所有分支都写 Lose"的复制粘贴 bug
    function test_regression_decisiveGameHasWinner() public {
        uint256[] memory cs = new uint256[](2);
        cs[0] = 1; cs[1] = 3; // 1 克 3
        GameResult[] memory exp = new GameResult[](2);
        exp[0] = GameResult.Win;
        exp[1] = GameResult.Lose;
        _runGameExpect(cs, exp);
    }

    function test_result_2p_sameChoice_equal() public {
        uint256[] memory cs = new uint256[](2);
        cs[0] = 2; cs[1] = 2;
        GameResult[] memory exp = new GameResult[](2);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Equal;
        _runGameExpect(cs, exp);
    }

    // 回归:超时结算不得产生 Win(防"看牌后选择性弃局"套利)
    function test_regression_timeoutNeverAwardsWin() public {
        uint256[] memory cs = new uint256[](3);
        cs[0] = 1; cs[1] = 3; cs[2] = 0; // 表面上 1 克 3,但有人弃局
        GameResult[] memory exp = new GameResult[](3);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Equal;
        exp[2] = GameResult.Lose;
        _runGameExpect(cs, exp);
    }

    // 当前设计:无人揭示 → 全员 Equal(资金处理另行约定,不在本套件范围)
    function test_result_noReveal_allEqual() public {
        uint256[] memory cs = new uint256[](3);
        GameResult[] memory exp = new GameResult[](3);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Equal;
        exp[2] = GameResult.Equal;
        _runGameExpect(cs, exp);
    }

    // 2 人穷举:4×4 = 16 局(含弃局),全部对照独立预言机
    function test_exhaustive_2players() public {
        for (uint256 a = 0; a <= 3; ++a) {
            for (uint256 b = 0; b <= 3; ++b) {
                uint256[] memory cs = new uint256[](2);
                cs[0] = a; cs[1] = b;
                _runGame(cs);
            }
        }
    }

    // 3 人穷举:4×4×4 = 64 局(含弃局/全弃局/超时/自动结算所有路径)
    function test_exhaustive_3players() public {
        for (uint256 a = 0; a <= 3; ++a) {
            for (uint256 b = 0; b <= 3; ++b) {
                for (uint256 c = 0; c <= 3; ++c) {
                    uint256[] memory cs = new uint256[](3);
                    cs[0] = a; cs[1] = b; cs[2] = c;
                    _runGame(cs);
                }
            }
        }
    }

    function testFuzz_fullGame_allRevealed(uint256 seed) public {
        uint256 n = bound(seed, 2, 8);
        uint256[] memory cs = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            cs[i] = uint256(keccak256(abi.encode(seed, i))) % 3 + 1;
        }
        _runGame(cs);
    }

    function testFuzz_fullGame_mixedWithTimeout(uint256 seed) public {
        uint256 n = bound(seed, 2, 8);
        uint256[] memory cs = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            cs[i] = uint256(keccak256(abi.encode(seed, i))) % 4; // 0 = 弃局
        }
        _runGame(cs);
    }

    function test_largeRoom_16players() public {
        uint256[] memory cs = new uint256[](16);
        for (uint256 i = 0; i < 16; ++i) cs[i] = i % 3 + 1;
        _runGame(cs); // 同时验证 16 条事件的数量与顺序
    }

    // ================================================================
    //                          DDL
    // ================================================================

    // DDL 锚定"最后一笔 choose"的时间戳;边界:DDL-1 不结算,恰好 DDL 结算(>=)
    function test_ddl_anchoredToLastChoose_boundary() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        guess.choose(id, _hash(1, _salt(id, 0), ps[0], id));
        vm.warp(T0 + 50);
        vm.prank(ps[1]);
        guess.choose(id, _hash(1, _salt(id, 1), ps[1], id)); // DDL = T0+50+100

        vm.prank(ps[0]);
        guess.commit(id, 1, _salt(id, 0)); // 1/2 揭示

        vm.warp(T0 + 149);
        guess.checkDDL(id); // 未到期:静默 no-op(当前设计)
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Committing));

        vm.warp(T0 + 150);
        GameResult[] memory exp = new GameResult[](2);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Lose;
        _expectResults(ps, exp, id);
        guess.checkDDL(id);
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Locked));
    }

    function test_ddl_anyoneCanCall() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        _chooseAll(id, ps, _twoChoices(1, 0));
        vm.prank(ps[0]);
        guess.commit(id, 1, _salt(id, 0));
        vm.warp(block.timestamp + DDL_LEN + 1);

        GameResult[] memory exp = new GameResult[](2);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Lose;
        _expectResults(ps, exp, id);
        vm.prank(STRANGER); // 无权限要求,任何人可触发
        guess.checkDDL(id);
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Locked));
    }

    function test_ddl_reverts_wrongStage() public {
        uint256 idGathering = _setup(_players(2));
        vm.expectRevert("Game not committing");
        guess.checkDDL(idGathering);

        (uint256 idLocked,) = _runGame(_twoChoices(1, 3));
        vm.expectRevert("Game not committing");
        guess.checkDDL(idLocked);
    }

    // 设计选择:Gathering 无超时。卡死是玩家不配合的后果(已确认接受)
    function test_gathering_noTimeout_byDesign() public {
        address[] memory ps = _players(2);
        uint256 id = _setup(ps);
        vm.prank(ps[0]);
        guess.choose(id, _hash(1, _salt(id, 0), ps[0], id));

        vm.warp(T0 + 365 days);
        vm.expectRevert("Game not committing");
        guess.checkDDL(id);
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Gathering));

        vm.prank(ps[1]); // 一年后仍可继续
        guess.choose(id, _hash(1, _salt(id, 1), ps[1], id));
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Committing));
    }

    function test_ddl_len1_works() public {
        address[] memory ps = _players(2);
        vm.prank(FOUNDER);
        uint256 id = guess.setupGame(ps, 1);
        _chooseAll(id, ps, _twoChoices(1, 0));
        vm.prank(ps[0]);
        guess.commit(id, 1, _salt(id, 0));
        vm.warp(block.timestamp + 1);

        GameResult[] memory exp = new GameResult[](2);
        exp[0] = GameResult.Equal;
        exp[1] = GameResult.Lose;
        _expectResults(ps, exp, id);
        guess.checkDDL(id);
        assertEq(uint8(guess.getStage(id)), uint8(GameStage.Locked));
    }

    // ================================================================
    //                      阶段机 / 房间隔离
    // ================================================================

    function test_locked_allActionsRevert() public {
        (uint256 id, address[] memory ps) = _runGame(_twoChoices(1, 3));
        vm.prank(ps[0]);
        vm.expectRevert("Game not gathering");
        guess.choose(id, bytes32(uint256(1)));
        vm.prank(ps[0]);
        vm.expectRevert("Game not committing");
        guess.commit(id, 1, _salt(id, 0));
        vm.expectRevert("Game not committing");
        guess.checkDDL(id);
    }

    function test_rooms_independent() public {
        (uint256 id0,) = _runGame(_twoChoices(1, 3));
        uint256 id1 = _setup(_players(2)); // 相同玩家开新房
        assertEq(uint8(guess.getStage(id0)), uint8(GameStage.Locked));
        assertEq(uint8(guess.getStage(id1)), uint8(GameStage.Gathering));
        (uint256 id2, address[] memory ps2) = _roomCommitting(2);
        assertEq(uint8(guess.getStage(id2)), uint8(GameStage.Committing));
        assertEq(uint8(guess.getStage(id0)), uint8(GameStage.Locked)); // 互不影响
        assertEq(ps2.length, 2);
    }

    function test_getStage_invalidRoom_panics() public {
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x32));
        guess.getStage(999);
    }

    function _twoChoices(uint256 a, uint256 b) internal pure returns (uint256[] memory cs) {
        cs = new uint256[](2);
        cs[0] = a;
        cs[1] = b;
    }
}