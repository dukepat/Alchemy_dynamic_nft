// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// Chainlink Imports
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// This import includes functions from both ./KeeperBase.sol and
// ./interfaces/KeeperCompatibleInterface.sol
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

// Dev imports. This only works on a local dev network
// and will not work on any test or main livenets.
import "hardhat/console.sol";

contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable, KeeperCompatible, VRFConsumerBaseV2 {
    using SafeMath for uint;
    using Counters for Counters.Counter;
    VRFCoordinatorV2Interface COORDINATOR;
    // Your subscription ID.
    uint64 s_subscriptionId;

    // Rinkeby coordinator. For other networks,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    // address vrfCoordinator; /* = 0x6168499c0cFfCaCD319c818142124B7A15E857ab*/

    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf-contracts/#configurations
    bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;

    uint32 callbackGasLimit = 500000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // For this example, retrieve 2 random values in one request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords =  1;

    uint256[] public s_randomWords;
    uint256 public s_requestId;
    address s_owner;


    Counters.Counter private _tokenIdCounter;
    uint public interval;
    uint public lastTimestamp;
    AggregatorV3Interface public priceFeed;
    int256 public currentPrice;
    enum MarketTrend{ BULL, BEAR }

    MarketTrend public currentMarketTrend;

     // IPFS URIs for the dynamic nft graphics/metadata.
    // NOTE: These connect to my IPFS Companion node.
    // You should upload the contents of the /ipfs folder to your own node for development.
    string[] bullUrisIpfs = [
        "https://ipfs.filebase.io/ipfs/QmQrKA89esBaednLtS88xgy34XPWe3WdfgL61sD7LDtDjg?filename=gamer_bull.json",
        "https://ipfs.filebase.io/ipfs/QmSwMQkcMUsgw7Bv9EWBje4JAnxYeUhhkuw6Z8NyTvqgsY?filename=party_bull.json",
        "https://ipfs.filebase.io/ipfs/Qma4p8nm6ecrncP8jKdmkpAUsnukLUQ556z9aecNedgEux?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.filebase.io/ipfs/QmTqtXfW7FnBu3BK193CJR2gpoCNEuvLPRf1ZpPbaaUJH9?filename=beanie_bear.json",
        "https://ipfs.filebase.io/ipfs/QmcC5VCweRiX2hGos9vUVj2RuYW14RuDZF2c17GWZSyGfG?filename=coolio_bear.json",
        "https://ipfs.filebase.io/ipfs/QmdiFWrT5wqzWav26LJS9Xr31ftZusJyJhd6f5M3x7yDgt?filename=simple_bear.json"
    ];

    event TokensUpdated(string marketTrend);

    constructor(uint updateInterval, address _priceFeed, address _vrfCoordinator) VRFConsumerBaseV2(_vrfCoordinator) ERC721("Bull&Bear", "BBTK") {
        interval = updateInterval;
        lastTimestamp = block.timestamp;
        s_subscriptionId = 6167;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);

        // set the price feed address to
        // BTC/USD
        priceFeed = AggregatorV3Interface(_priceFeed);

        currentPrice = getLatestPrice();
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);

         // Default to a bull NFT
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);

        console.log(
            "DONE!!! minted token ",
            tokenId,
            " and assigned token url: ",
            defaultUri
        );
    }

    // Assumes the subscription is funded sufficiently.
    function requestRandomWords() internal {
        require(s_subscriptionId != 0, "Subscription ID not set"); 
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
        keyHash,
        s_subscriptionId,
        requestConfirmations,
        callbackGasLimit,
        numWords
        );

        console.log("Request ID: ", s_requestId);
    }

    function fulfillRandomWords(uint256, /*requestId*/ uint256[] memory randomWords) internal override {
        s_randomWords = randomWords;

        console.log("...Fulfilling random Words");
        
        string[] memory urisForTrend = currentMarketTrend == MarketTrend.BULL ? bullUrisIpfs : bearUrisIpfs;
        uint256 idx = s_randomWords[0] % urisForTrend.length; // use modulo to choose a random index.


        for (uint i = 0; i < _tokenIdCounter.current() ; i++) {
            _setTokenURI(i, urisForTrend[idx]);
        } 

        string memory trend = currentMarketTrend == MarketTrend.BULL ? "bullish" : "bearish";
        
        emit TokensUpdated(trend);
        }

    function checkUpkeep(bytes calldata /*checkData*/) external view override returns(bool upkeepNeeded, bytes memory /*performData*/) {
        upkeepNeeded = (block.timestamp -lastTimestamp) > interval;

        }

    function performUpkeep(bytes calldata /*performData*/) external override {
        uint lapseTime = block.timestamp - lastTimestamp;
        require( lapseTime > interval, "Upkeep interval not reached");
        requestRandomWords();
        lastTimestamp = block.timestamp;
        int latestPrice = getLatestPrice();

        if(latestPrice == currentPrice) {
            return;
        }
        if(latestPrice < currentPrice) {
            // bear
            currentMarketTrend = MarketTrend.BEAR;
        } else {
            //bull
            currentMarketTrend = MarketTrend.BULL;
            }
        requestRandomWords();
        currentPrice = latestPrice;
    }
    // Helpers
    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b))); 
    }
    // setter for the interval
    function setInterval(uint256 newInterval) public onlyOwner {
        interval = newInterval;
    }

    function setPriceFeed(address newFeed) public onlyOwner {
        priceFeed = AggregatorV3Interface(newFeed);
    }

    
    // Setter function for subscription ID
    function setSubscriptionId(uint64 _subscriptionId) public onlyOwner{
        s_subscriptionId = _subscriptionId;
    }

    // Setter function for the
    function setVRFCoordinator(address _vrfCoordinator) public onlyOwner{
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
    }

    // setter for callbackGasLimit
    function setMaxGasLimit(uint32 maxGas) public onlyOwner {
      callbackGasLimit = maxGas;
    }

    function addBullUri(string memory _uri) public onlyOwner returns(string memory){
        bullUrisIpfs.push(_uri);
        return("Operation succeeded, bulluri added");
    }

    // The following functions will add and remove URIs in the future
    function addBearUri(string memory _uri) public onlyOwner returns(string memory){
        bearUrisIpfs.push(_uri);
        return("Operation succeeded, bearuri added");
    }
    function removeBullUri(uint index)  public onlyOwner returns(string memory){
        require(index <= bullUrisIpfs.length && index >=0, "index entered is invalid");

        for (uint i = index; i<bullUrisIpfs.length-1; i++){
            bullUrisIpfs[i] = bullUrisIpfs[i+1];
        }
        bullUrisIpfs.pop();
        return("Operation succeeded, bulluri removed");

    }

    function removeBearUri(uint index)  public  onlyOwner returns(string memory){
        require(index <= bearUrisIpfs.length && index >=0, "index entered is invalid");

        for (uint i = index; i<bearUrisIpfs.length-1; i++){
            bearUrisIpfs[i] = bearUrisIpfs[i+1];
        }
        bearUrisIpfs.pop();
        return("Operation succeeded, bearuri removed");
    }

    function getLatestPrice() public view returns(int256) {
        (
        /*uint80 roundId*/,
        int256 answer,
        /*uint256 startedAt*/,
        /*uint256 updatedAt*/,
        /*uint80 answeredInRound*/
    ) = priceFeed.latestRoundData();
    // example price returned 
    return answer;
    }





    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}