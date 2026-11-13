// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

enum GameStage {
    Available,
    Gathering,
    Committing
}

enum GameResult {
    Win,
    Lose,
    Equal
}

contract Guess {
    address[] players;
    bytes32[] hashes;
    uint256[] choices;
    uint256 curr_count;
    uint256 DDL;
    uint256 DDL_LEN;
    bool lock;
    uint256 gameId;

    mapping(address => bool) private selected;

    GameStage private stage;

    event Result(address indexed player, GameResult indexed result, uint256 gameId);

    error Busy();

    modifier locker() {
        if (lock) revert Busy();
        lock = true;
        _;
        lock = false;
    }

    constructor() {
        gameId = 0;
    }

    function invited() internal view returns (uint256) {
        uint256 player_id = getIndex(msg.sender);
        require(player_id != getAmount(), "Not invited");
        return player_id;
    }

    function getAmount() private view returns (uint256) {
        return players.length;
    }

    function getStage() external view returns (GameStage) {
        return stage;
    }

    function getGameId() external view returns (uint256) {
        return gameId;
    }

    function getIndex(address target) private view returns (uint256) {
        for (uint256 i = 0; i < getAmount(); ++i) {
            if (players[i] == target) {
                return i;
            }
        }
        return getAmount();
    }

    function clearGame() private {
        stage = GameStage.Available;
        delete hashes;
        delete players;
        delete choices;
        curr_count = DDL = 0;
        DDL_LEN = 2 days;
    }

    function setupGame(
        address[] calldata _players,
        uint256 _DDL_LEN
    ) public locker {
        require(stage == GameStage.Available, "Game not available");
        require(
            _players.length > 1,
            "Amount of players must be greater than 1"
        );
        require(_DDL_LEN > 0, "Deadline must be greater than 0");
        for(uint256 i = 0; i < _players.length; ++i) {
          require(selected[_players[i]] == false, "Duplicate player");
          require(_players[i] != address(0), "Invalid player");
          selected[_players[i]] = true;
        }
        for(uint256 i = 0; i < _players.length; ++i) {
          delete selected[_players[i]];
        }

        stage = GameStage.Gathering;

        for (uint256 i = 0; i < _players.length; ++i) {
            players.push(_players[i]);
            hashes.push(0);
            choices.push(0);
        }

        curr_count = 0;
        DDL = 0;
        DDL_LEN = _DDL_LEN;
        ++gameId;
    }

    function choose(bytes32 choice) external locker {
        require(stage == GameStage.Gathering, "Game not gathering");
        uint256 player_id = invited();
        require(hashes[player_id] == 0, "Your choice has been determined");
        require(choice != 0, "Can't commit 0 hash");
        hashes[player_id] = choice;
        curr_count++;

        if (curr_count == getAmount()) {
            curr_count = 0;
            stage = GameStage.Committing;
            DDL = block.timestamp + DDL_LEN;
        }
    }

    function commit(uint256 choice, uint salt) external locker {
        require(stage == GameStage.Committing, "Game not committing");
        uint256 player_id = invited();
        require(choice == 1 || choice == 2 || choice == 3, "Invalid choice");
        require(choices[player_id] == 0, "Your choice has been committed");
        require(
            keccak256(abi.encode(choice, salt, msg.sender, gameId)) == hashes[player_id],
            "Not correct"
        );

        choices[player_id] = choice;

        ++curr_count;
        if (curr_count == getAmount()) {
            summarize();
        }
    }

    function checkDDL() external locker {
        require(stage == GameStage.Committing, "Game not committing");
        if (DDL > 0 && block.timestamp >= DDL) {
            summarize();
        }
    }

    function checkResult() private {
        uint256[3] memory counts;
        for (uint256 i = 0; i < getAmount(); ++i) {
            if (choices[i] != 0) {
                counts[choices[i] - 1]++;
            }
        }

        uint256 positive_count = (counts[0] > 0 ? 1 : 0) +
            (counts[1] > 0 ? 1 : 0) +
            (counts[2] > 0 ? 1 : 0);
        if (positive_count == 1 || positive_count == 3) {
            for (uint256 i = 0; i < getAmount(); ++i) {
              if(choices[i] == 0) {emit Result(players[i], GameResult.Lose, gameId);}
                else {emit Result(players[i], GameResult.Equal, gameId);}
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

            for (uint256 i = 0; i < getAmount(); ++i) {
                if (choices[i] == 0 || choices[i] == ch2) {
                    emit Result(players[i], GameResult.Lose, gameId);
                } else {
                    emit Result(players[i], GameResult.Win, gameId);
                }
            }
        }
    }

    function summarize() private {
        checkResult();
        clearGame();
    }
}
