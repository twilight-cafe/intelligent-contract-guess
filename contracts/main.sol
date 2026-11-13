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
    mapping(address => bytes32) choiceHashes;
    address[2] addresses;
    uint256[2] choices;
    uint256 count;
    uint256 DDL;
    bool lock;

    GameStage private stage;

    event Result(address indexed player, GameResult indexed result);

    error Busy();

    modifier invited() {
        require(hasPlayer(msg.sender), "Not invited");
        _;
    }

    modifier locker() {
        if (lock) revert Busy();
        lock = true;
        _;
        lock = false;
    }

    function getStage() external view returns (GameStage) {
        return stage;
    }

    function clearGame() private {
        for (uint256 i = 0; i < 2; ++i) {
            delete choiceHashes[addresses[i]];
        }
        stage = GameStage.Available;
    }

    function setupGame(address[2] calldata players) external locker {
        require(stage == GameStage.Available, "Game not available");
        stage = GameStage.Gathering;
        addresses[0] = players[0];
        addresses[1] = players[1];
        choices[0] = choices[1] = 0;
        count = 0;
        DDL = 0;
    }

    function hasPlayer(address player) private view returns (bool ok) {
        ok = false;
        for (uint32 i = 0; i < 2; ++i) {
            if (addresses[i] == player) {
                ok = true;
                return ok;
            }
        }
    }

    function choose(bytes32 choice) external invited {
        require(stage == GameStage.Gathering, "Game not gathering");
        choiceHashes[msg.sender] = choice;
        count++;

        if (count == 2) {
            count = 0;
            stage = GameStage.Committing;
        }
    }

    function commit(uint256 choice, uint salt) external invited {
        require(stage == GameStage.Committing, "Game not committing");
        require(choice == 1 || choice == 2 || choice == 3, "Invalid choice");
        require(
            keccak256(abi.encode(choice, salt)) == choiceHashes[msg.sender],
            "Not correct"
        );

        for (uint256 i = 0; i < 2; ++i) {
            if (addresses[i] == msg.sender) {
                choices[i] = choice;
                break;
            }
        }

        ++count;
        if (count == 1) {
            DDL = block.timestamp + (2 days);
        }

        if (count == 2) {
            summarize();
        }
    }

    function checkDDL() external {
        require(stage == GameStage.Committing, "Game not committing");
        if (DDL > 0 && block.timestamp > DDL) {
            summarize();
        }
    }

    function summarize() private {
        if (choices[0] == 0) {
            emit Result(addresses[0], GameResult.Lose);
            emit Result(addresses[1], GameResult.Win);
        } else if (choices[1] == 0) {
            emit Result(addresses[0], GameResult.Win);
            emit Result(addresses[1], GameResult.Lose);
        } else if (choices[0] == choices[1]) {
            emit Result(addresses[0], GameResult.Equal);
            emit Result(addresses[1], GameResult.Equal);
        } else if (
            choices[0] == choices[1] + 1 || choices[0] == choices[1] - 2
        ) {
            emit Result(addresses[0], GameResult.Win);
            emit Result(addresses[1], GameResult.Lose);
        } else {
            emit Result(addresses[0], GameResult.Lose);
            emit Result(addresses[1], GameResult.Win);
        }

        stage = GameStage.Available;
    }
}
