// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct KamisamaConfig {
    address owner;
    address treasury;
    uint256 cost;
    address lzEndpoint;
    uint32 lzEndpointIDLinked;
    address heroglyphsRelayer;
    address gasPool;
    address heroglyphsRelayExtension;
    address identityRouter;
    PreviousBlockProducer[] pastBlockProducer;
}

struct PreviousBlockProducer {
    string validatorName;
    uint32 validatorIndex;
}

string constant CONFIG_FILE = "KamisamaConfig";
string constant KAMISAMA = "Kamisama";
string constant KAMISAMA_HEROGLYPHS = "KamisamaTicker";
string constant MAINNET = "ethereum";
string constant ARBITRUM = "arbitrum";
