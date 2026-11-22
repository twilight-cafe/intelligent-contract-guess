// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum GameStage {
    Available,
    Gathering,
    Committing,
    Locked
}

enum GameResult {
    Win,
    Lose,
    Equal,
    Illegal
}

contract Guess {
    struct Room {
        address[] players;
        bytes32[] hashes;
        uint256[] choices;
        GameResult[] results;
        uint256 curr_count;
        uint256 DDL;
        uint256 DDL_LEN;
        bool lock;
        GameStage stage;
        uint256 bond;
        uint256 stake;
        uint256[] toPay;
    }

    Room[] rooms;
    address SakurakoujiLuna;
    uint256 toLuna;

    event Result(
        address indexed player,
        GameResult indexed result,
        uint256 gameId
    );

    error Busy();
    error FailurePay();

    constructor(address payable skrkj) {
        require(skrkj != address(0), "Must specify a valid address.");
        SakurakoujiLuna = skrkj;
        toLuna = 0;
    }

    modifier locker(uint256 roomId) {
        if (rooms[roomId].lock) revert Busy();
        rooms[roomId].lock = true;
        _;
        rooms[roomId].lock = false;
    }

    function invited(uint256 roomId) internal view returns (uint256) {
        uint256 player_id = getIndex(roomId, msg.sender);
        require(player_id != getAmount(roomId), "Not invited");
        return player_id;
    }

    function getAmount(uint256 roomId) private view returns (uint256) {
        return rooms[roomId].players.length;
    }

    function getIndex(
        uint256 roomId,
        address target
    ) private view returns (uint256) {
        for (uint256 i = 0; i < getAmount(roomId); ++i) {
            if (rooms[roomId].players[i] == target) {
                return i;
            }
        }
        return getAmount(roomId);
    }

    function setupGame(
        address[] calldata _players,
        uint256 _DDL_LEN,
        uint256 bond,
        uint256 stake
    ) public returns (uint256 newGameRoomId) {
        require(
            _players.length > 1,
            "Amount of players must be greater than 1"
        );
        require(_DDL_LEN > 0, "Deadline must be greater than 0");
        require(bond > 0, "bond should be greater than 0");
        require(stake > 0, "stake should be greater than 0");
        require(bond > stake, "bond should be greater than stake");

        // 天翼 2G 真是太快啦(O(n ^ 2))
        for (uint256 i = 0; i < _players.length; ++i) {
            require(_players[i] != address(0), "Invalid player");
            for (uint256 j = i + 1; j < _players.length; ++j) {
                require(_players[i] != _players[j], "Duplicate player");
            }
        }

        Room storage ref = rooms.push();
        ref.lock = true;
        ref.stage = GameStage.Gathering;

        for (uint256 i = 0; i < _players.length; ++i) {
            ref.players.push(_players[i]);
            ref.hashes.push(bytes32(0));
            ref.choices.push(0);
            ref.results.push();
            ref.toPay.push(0);
        }

        ref.DDL_LEN = _DDL_LEN;

        ref.lock = false;
        ref.bond = bond;
        ref.stake = stake;
        return rooms.length - 1;
    }

    function choose(
        uint256 roomId,
        bytes32 choice
    ) external payable locker(roomId) {
        require(
            rooms[roomId].stage == GameStage.Gathering,
            "Game not gathering"
        );
        uint256 player_id = invited(roomId);
        require(
            rooms[roomId].hashes[player_id] == 0,
            "Your choice has been determined"
        );
        require(choice != 0, "Can't commit 0 hash");

        require(
            msg.value == rooms[roomId].bond + rooms[roomId].stake,
            "Not accurately the number"
        );
        rooms[roomId].hashes[player_id] = choice;
        rooms[roomId].curr_count++;

        if (rooms[roomId].curr_count == getAmount(roomId)) {
            rooms[roomId].curr_count = 0;
            rooms[roomId].stage = GameStage.Committing;
            rooms[roomId].DDL = block.timestamp + rooms[roomId].DDL_LEN;
        }
    }

    function commit(
        uint256 roomId,
        uint256 choice,
        bytes32 salt
    ) external locker(roomId) {
        require(block.timestamp < rooms[roomId].DDL, "Too late.");
        require(
            rooms[roomId].stage == GameStage.Committing,
            "Game not committing"
        );
        uint256 player_id = invited(roomId);
        require(choice == 1 || choice == 2 || choice == 3, "Invalid choice");
        require(
            rooms[roomId].choices[player_id] == 0,
            "Your choice has been committed"
        );
        require(
            keccak256(abi.encode(choice, salt, msg.sender, roomId)) ==
                rooms[roomId].hashes[player_id],
            "Not correct"
        );

        rooms[roomId].choices[player_id] = choice;

        ++rooms[roomId].curr_count;
        if (rooms[roomId].curr_count == getAmount(roomId)) {
            summarize(roomId);
        }
    }

    function checkDDL(
        uint256 roomId
    ) external locker(roomId) returns (bool summarized) {
        require(
            rooms[roomId].stage == GameStage.Committing,
            "Game not committing"
        );
        if (rooms[roomId].DDL > 0 && block.timestamp >= rooms[roomId].DDL) {
            summarize(roomId);
            summarized = true;
        }
        return summarized;
    }

    function checkResult(uint256 roomId) private {
        uint256[3] memory counts;
        for (uint256 i = 0; i < getAmount(roomId); ++i) {
            if (rooms[roomId].choices[i] != 0) {
                counts[rooms[roomId].choices[i] - 1]++;
            }
        }

        uint256 positive_count = (counts[0] > 0 ? 1 : 0) +
            (counts[1] > 0 ? 1 : 0) +
            (counts[2] > 0 ? 1 : 0);
        if (positive_count == 0) {
            for (uint256 i = 0; i < getAmount(roomId); ++i) {
                rooms[roomId].results[i] = GameResult.Illegal;
            }
        } else if (
            positive_count == 1 ||
            positive_count == 3 ||
            rooms[roomId].curr_count != getAmount(roomId)
        ) {
            for (uint256 i = 0; i < getAmount(roomId); ++i) {
                if (rooms[roomId].choices[i] == 0) {
                    rooms[roomId].results[i] = GameResult.Illegal;
                } else {
                    rooms[roomId].results[i] = GameResult.Equal;
                }
            }
        } else {
            // Win
            uint256 ch1 = counts[0] > 0 ? 1 : 2;
            // Lose
            uint256 ch2 = counts[2] > 0 ? 3 : 2;
            if (ch1 == ch2 - 1) {
                uint256 ch_tmp = ch1;
                ch1 = ch2;
                ch2 = ch_tmp;
            }

            for (uint256 i = 0; i < getAmount(roomId); ++i) {
                if (
                    rooms[roomId].choices[i] == 0 ||
                    rooms[roomId].choices[i] == ch2
                ) {
                    rooms[roomId].results[i] = GameResult.Lose;
                } else {
                    rooms[roomId].results[i] = GameResult.Win;
                }
            }
        }
    }

    function emitAll(uint256 roomId) private {
        for (uint256 i = 0; i < rooms[roomId].players.length; ++i) {
            emit Result(
                rooms[roomId].players[i],
                rooms[roomId].results[i],
                roomId
            );
        }
    }

    function calculate(uint256 roomId) private {
        uint256 pool = 0;
        uint256 count = 0;
        uint256 count_equal = 0;
        uint256 count_win = 0;
        for (uint256 i = 0; i < getAmount(roomId); ++i) {
            if (rooms[roomId].results[i] == GameResult.Illegal) {
                pool += rooms[roomId].bond + rooms[roomId].stake;
                ++count;
            }
            if (rooms[roomId].results[i] == GameResult.Equal) {
                ++count_equal;
            }
            if (rooms[roomId].results[i] == GameResult.Win) {
                ++count_win;
            }
        }
        count = getAmount(roomId) - count;

        if (count != 0 && count_equal == 0) {
            pool = rooms[roomId].stake * getAmount(roomId);
            uint256 bonus = pool / count_win;
            uint256 remainder = pool % count_win;
            toLuna += remainder;

            for (uint256 i = 0; i < getAmount(roomId); ++i) {
                if (rooms[roomId].results[i] == GameResult.Win) {
                    rooms[roomId].toPay[i] = bonus + rooms[roomId].bond;
                } else if (rooms[roomId].results[i] == GameResult.Lose) {
                    rooms[roomId].toPay[i] = rooms[roomId].bond;
                }
            }
        } else if (count == 0) {
            // 不要白不要
            toLuna =
                toLuna +
                getAmount(roomId) * (rooms[roomId].stake + rooms[roomId].bond);
        } else {
            uint256 bonus = pool / count;
            uint256 remainder = pool % count;
            toLuna += remainder;

            for (uint256 i = 0; i < getAmount(roomId); ++i) {
                if (rooms[roomId].results[i] != GameResult.Illegal) {
                    rooms[roomId].toPay[i] =
                        bonus +
                        rooms[roomId].bond +
                        rooms[roomId].stake;
                }
            }
        }
    }

    function summarize(uint256 roomId) private {
        checkResult(roomId);
        emitAll(roomId);
        rooms[roomId].stage = GameStage.Locked;
        calculate(roomId);
    }

    function getMoney(uint256 roomId) external locker(roomId) {
        require(rooms[roomId].stage == GameStage.Locked, "Game not locked");
        uint256 player_id = invited(roomId);

        uint256 tmp = rooms[roomId].toPay[player_id];
        require(tmp > 0, "No money for you");
        rooms[roomId].toPay[player_id] = 0;

        (bool ok, ) = payable(msg.sender).call{value: tmp}("");

        if (!ok) {
            revert FailurePay();
        }
    }

    function getLunaMoney() external {
        require(msg.sender == SakurakoujiLuna, "Who are you");
        uint256 tmp = toLuna;
        toLuna = 0;
        (bool ok, ) = payable(SakurakoujiLuna).call{value: tmp}("");
        if (!ok) {
            revert FailurePay();
        }
    }

    function getStage(uint256 roomId) external view returns (GameStage) {
        return rooms[roomId].stage;
    }

    function getHash(
        uint256 choice,
        bytes32 salt,
        address sender,
        uint256 roomId
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(choice, salt, sender, roomId));
    }
}
