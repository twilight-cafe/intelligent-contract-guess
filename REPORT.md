[GitHub](https://github.com/twilight-cafe/intelligent-contract-guess)

# 猜拳游戏合约

## 概述

这是一个安全公平平等的猜拳游戏。

1. 支持多人游戏（任意人数，但是不建议太多）（胜负规则针对多人情况进行了针对性修改）。
2. 支持多房间游戏，不同房间互不干扰。
3. 链上仅存储选项哈希（含盐，盐由玩家指定，可以是随机字符串，除此之外还含有链 id 等信息），全部玩家提交后再揭露。DDL 后揭露的视为非法玩家。
4. 支持添加押金。
5. 支持向 constructor 调用者 donate。

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

## 代码设计

源代码采用**古法编程**，单元测试由 AI 生成。

- `constructor(address payable skrkj)`：负责收各种各样的钱，例如粉尘余额，或者所有玩家都不揭露时的 donate 对象。
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

## 安全性分析

### 猜拳结果认定

- 若全员超时：视为 donate，所有钱留给 constructor 调用者。
- 若有人未揭露：平局。虽然有人未揭露也可以计算余下的玩家的游戏结果并计算出胜负，但是此时恶意玩家可以创建小号，做不同的选择并在其他人全部揭露后，视情况揭露其中的一个小号的结果，从而实现盈利，只需要获胜所得大于押金即可持续盈利，这不安全，故但凡有玩家未揭露，则已经揭露者平局。
- 若猜拳种类数为 $1$ 或者 $3$：平局，所有人平分钱。
- 若猜拳种类数为 $2$：按照 $3$ 胜 $2$，$2$ 胜 $1$，$1$ 胜 $3$ 顺序判断胜负。

### 奖金分配

- 粉尘余额以及 donation 收给 constructor。
- 平局拿回自己的钱。
- 所有胜者平分所有败者的押注（和自己的押金和押注），但是败者可以取回押金。

### 并发安全

- 主要外部函数均含 `modifier locker`，遇到锁会直接 `revert`，避免多人同时操作。

### 信息安全

- 揭露前采用哈希存储选择：` keccak256(abi.encode(choice, salt, msg.sender, roomId)`。

## 部署过程

Remix + Metamask 直接部署（合约地址：`0xe97C49FD6169428028Cf577F003Aa09A4b6DBDed`）。

## 测试与分析

- 利用单元测试框架自动测试（test/main.t.sol）。
- 手动测试。

##  AI 辅助

1. 检查代码的安全性。
2. 编写单元测试等测试文件。
3. 创建项目其他文件，如 `hardhat.config.ts`。

## 项目源码

项目仓库暂时可在 [Link](https://github.com/twilight-cafe/intelligent-contract-guess) 访问。
