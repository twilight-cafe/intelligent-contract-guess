# 猜拳游戏合约

## 功能：

1. 支持多人游戏。
2. 支持多房间游戏，不同房间互不干扰。
3. 链上仅存储选项哈希，全部玩家提交后再揭露。DDL 后揭露的视为非法玩家。
4. 支持添加押金。

## Git 迭代记录

```
commit 6d701e244a90dc5f95a6548d3c31a885f42ca67d
Author: Twilight <3011080608@qq.com>
Date:   Sun Nov 22 22:26:39 2026 +0800

    v0.4.0
    1. 添加付钱支持与押金支持。

commit ba1a5aece78e1074fc40a4a863584d3e7f03019d
Author: Twilight Cafe <3011080608@qq.com>
Date:   Sat Nov 14 13:00:53 2026 +0800

    v0.3.0
    1. 添加房间支持。
    2. 一旦有人未揭露，其余人平局。避免某人多个小号择优揭露。

commit 572c366ff6f4d542913fb9d56b4f14d6c21e1c80
Author: Twilight Cafe <3011080608@qq.com>
Date:   Fri Nov 13 23:39:11 2026 +0800

    v0.2.0
    1. 允许多人游戏。
    2. 更丰富的哈希内容。
    3. 允许设置 DDL 时间。

commit d9b79f866f360bb6fc3d6dfdb2b714028515d2ad
Author: Twilight Cafe <3011080608@qq.com>
Date:   Fri Nov 13 22:21:08 2026 +0800

    V0.1.0
    1. 支持双人猜拳。
    2. 支持全局锁，同一时间仅执行一个任务
    3. 玩家全部提交加盐哈希值后再统一揭露真实选项。固定时间后未揭露的视为失败。
```

## 接口与使用方法

- `constructor(address payable skrkj)`：负责收各种各样的钱，例如粉尘余额，或者所有玩家都不揭露时的友情赠送。
- `function setupGame(
          address[] calldata _players,// 玩家列表
          uint256 _DDL_LEN, // DDL
          uint256 bond, // 押金
          uint256 stake // 押注
      ) public returns (uint256 newGameRoomId)`：创建游戏房间。默认房主选择了愿意参与游戏的玩家，合约内部不会处理某玩家一直不提交选项的情况（但是会处理提交选项后一直不揭露的情况）。
- `function choose(
          uint256 roomId, // 所属房间
          bytes32 choice // 选项哈希
      ) external payable locker(roomId)`：提交选项。需要带上押金和押注。
- `function commit(
          uint256 roomId, // 所属房间
          uint256 choice, // 实际选项
          bytes32 salt // 盐
      ) external locker(roomId)`：揭露选项。所有玩家均提交后可用，否则报错。
- `function checkDDL(
          uint256 roomId // 所属房间
      ) external locker(roomId) returns (bool summarized)`：检查 DDL。
- `function getMoney(
        uint256 roomId // 所属房间
   ) external locker(roomId)`：提钱。仅在所有玩家均揭露或者揭露超时后可用。
- `function getLunaMoney()`：创建合约者提钱。
- `getStage(uint256 roomId) external view returns (GameStage)`：查询该房间进度。
- `getHash(
           uint256 choice,
           bytes32 salt,
           address sender,
           uint256 roomId
       ) external pure returns (bytes32)`：计算哈希结果的辅助函数，本地调试时用。不应该在链上调用。

## 结局计算方法与安全性

相关函数如下：

```solidity
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
```

若 `positive_count` 为 $0$ 表示全员超时。视为向合约创建者友情送钱。

若参与者选项种类数为 $1$ 或者 $3$，或者有人未揭露，则平局，所有合法玩家平分非法玩家的钱。虽然有人未揭露也可以计算余下的玩家的游戏结果并计算出胜负，但是恶意玩家可以创建小号，做不同的选择并在其他人全部揭露后，视情况揭露其中的一个小号的结果，从而实现盈利，只需要获胜所得大于押金即可持续盈利，这不好。

若所有人均揭露，并且选项种类数为 $2$，则判断胜负。$3$ 胜 $2$，$2$ 胜 $1$，$1$ 胜 $3$。

##  AI 辅助

1. 检查代码的安全性。
2. 编写单元测试等测试文件。
3. 创建项目其他文件，如 `hardhat.config.ts`。

源文件（main.sol）独立完成，未经由 AI 修改。

## 项目源码

项目仓库在被删除前可在[Link](https://github.com/twilight-cafe/intelligent-contract-guess)访问。
