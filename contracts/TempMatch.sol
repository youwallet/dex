
pragma solidity >=0.4.21 <0.6.0;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

contract TempMatch{
    using SafeMath for uint256;

    // signature
    struct OrderSignature {
        bytes32 config;
        bytes32 r;
        bytes32 s;
    }

    // Match info
    struct MatchedInfo{
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 gasAmount;
    }

    // order info
    struct OrderParam {
        address trader;
        uint256 baseAmount;
        uint256 quoteAmount;
        uint256 gasAmount;
        bytes32 data;
        OrderSignature signature;
    }

    // token set
    struct OrderAddressSet {
        address baseToken;
        address quoteToken;
        address relayer;
    }

    // queue element
    struct QueueElem {
        OrderParam order;
        uint256 next;
    }

    // queue
    struct Queue{
        mapping(uint256 => QueueElem) elems;
        uint256 start;
        uint256 end;
    }

    //  sell/buy queue 
    mapping(uint256 => Queue) public sellQueue;
    mapping(uint256 => Queue) public buyQueue;

    // order flag
    mapping(uint256 => bool) public orderFlag;

    /* proxy: address of proxy
     * dex: address of dex
     * */
    address public proxy;
    address public dex;

    event TakeOrder(address indexed trader, address indexed base, address indexed quote,
                    uint256 baseAmount, uint256 quoteAmount, uint256 gasAmount,
                    bool is_sell);
    event MakeOrder(address indexed trader, address indexed base, address indexed quote,
                    uint256 baseAmount, uint256 quoteAmount, uint256 gasAmount,
                    bool is_sell);
    event CancelOrder(address indexed trader, address indexed base, address indexed quote,
                    uint256 baseAmount, uint256 quoteAmount, bool is_sell);
    //event MatchOrder(address indexed taker,
    //                uint256 baseAmount, uint256 quoteAmount, bool is_sell);

    /* constructor
     * proxy: address of proxy
     * dex: address of dex
     * */
    constructor (address _proxy, address _dex) public
    {
        proxy = _proxy;
        dex = _dex;
    }

    function () external payable
    {
    }

    /* take order
     * base
     * base: base token   
     * quote: quote toke
     * baseAmount: amount of base token for 1 quote token
     * quoteAmount: amount of quote token
     * gasAmount: hot token amount
     * is_sell: true for sell, false for buy
     * return hash of order if doesn't match all quoteAmount
     * */
    function takeOrder(address base, address quote,
                       uint256 baseAmount, uint256 quoteAmount, uint256 gasAmount, bool is_sell)
        public
        returns (bytes32)
    {
        // hash of base-quote token
        uint256 bq_hash = uint256(keccak256(abi.encodePacked(
                                        bytes32(uint256(base)),
                                        bytes32(uint256(quote)))));

        // hash of order
        uint256 od_hash = uint256(keccak256(abi.encodePacked(
                                        bytes32(uint256(msg.sender)),
                                        baseAmount,
                                        quoteAmount,
                                        gasAmount,
                                        is_sell)));

        // mark order
        require(!orderFlag[od_hash]);
        orderFlag[od_hash] = true;

        OrderParam memory od;
        od.trader = msg.sender;
        od.baseAmount  = baseAmount;
        od.quoteAmount = quoteAmount;
        od.gasAmount = gasAmount;
        // TODO: data, signature
        //od.data = ;
        //od.signature = ;

        Queue storage queue  = sellQueue[bq_hash];
        Queue storage mqueue =  buyQueue[bq_hash];
        if(!is_sell)
        {
            queue  =  buyQueue[bq_hash];
            mqueue = sellQueue[bq_hash];
        }

        // match sell / buy
        MatchedInfo memory mi = match_orders(mqueue, od, is_sell);

        emit TakeOrder(msg.sender, base, quote,
                  mi.baseAmount, mi.quoteAmount, mi.gasAmount,
                  is_sell);

        od.quoteAmount =  od.quoteAmount.sub(mi.quoteAmount);
        od.gasAmount =  od.gasAmount.sub(mi.gasAmount);
        
        // full match
        if(od.quoteAmount == 0)
        {
            delete orderFlag[od_hash];
            return bytes32(0);
        }

        // use baseAmount for 1 quote token
        queue.elems[od_hash].order = od;

        // insert maker order
        insert_queue(queue, od_hash, baseAmount, is_sell);
        emit MakeOrder(msg.sender, base, quote, od.baseAmount, od.quoteAmount, od.gasAmount, is_sell);

        return bytes32(od_hash);
    }

    /* get base-quote-hash
     * base: base token
     * quote: quote token
     * */
    function getBQHash(address base, address quote) public pure returns(uint256 bq_hash)
    {
        bq_hash = uint256(keccak256(abi.encodePacked(
                                bytes32(uint256(base)),
                                bytes32(uint256(quote)))));
    }

    /* cancel order
     * odh: order-hash
     * base: base token
     * quote: quote token
     * is_sell: true for sell, false for buy
     * */
    function cancelOrder (bytes32 odh, address base, address quote, bool is_sell) public
    {
        // hash of base-quote token
        uint256 bq_hash = uint256(keccak256(abi.encodePacked(
                                        bytes32(uint256(base)),
                                        bytes32(uint256(quote)))));
        uint256 od_hash = uint256(odh);

        // exists
        require(orderFlag[od_hash]);

        // get queue
        Queue storage queue  = sellQueue[bq_hash];
        if(!is_sell)
            queue  =  buyQueue[bq_hash];

        OrderParam storage order = queue.elems[od_hash].order;
        uint256 baseAmount = order.baseAmount;
        uint256 quoteAmount = order.quoteAmount;

        // delete order
        remove_queue(queue, od_hash);
        delete orderFlag[od_hash];

        emit CancelOrder(msg.sender, base, quote, baseAmount, quoteAmount, is_sell);
    }

    // match sell/buy
    function match_orders(Queue storage queue,
                          OrderParam memory taker,
                          bool is_sell)
        internal
        returns(MatchedInfo memory mi)
    {
        uint256 odh = queue.start;
        uint256 next;
        while(odh != 0)
        {
            OrderParam storage maker = queue.elems[odh].order;
            next = queue.elems[odh].next;
            if((is_sell  && taker.baseAmount < maker.baseAmount) ||
               (!is_sell && taker.baseAmount > maker.baseAmount))
            {
                if(taker.quoteAmount >= maker.quoteAmount)
                {
                    mi.baseAmount = mi.baseAmount.add(maker.quoteAmount.mul(maker.quoteAmount));
                    mi.quoteAmount = mi.quoteAmount.add(maker.quoteAmount);
                    taker.quoteAmount = taker.quoteAmount.sub(maker.quoteAmount);
                    maker.quoteAmount = 0;
                    remove_queue(queue, odh);
                }
                else
                {
                    mi.baseAmount = mi.baseAmount.add(taker.quoteAmount.mul(maker.quoteAmount));
                    mi.quoteAmount = mi.quoteAmount.add(taker.quoteAmount);
                    maker.quoteAmount = maker.quoteAmount.sub(taker.quoteAmount);
                    taker.quoteAmount = 0;
                    break;
                }
            }
            else
            {
                break;
            }
            odh = next;
        }
        //emit MatchOrder(taker.trader, baseAmount, quoteAmount, is_sell);
    }

    // insert sell/buy queue
    function insert_queue(Queue storage queue,
                          uint256 od_hash,
                          uint256 baseAmount,
                          bool is_sell)
        internal
    {
        // empty queue
        if (queue.start == 0 &&
            queue.end == 0)
        {
            queue.start = od_hash;
            queue.end = od_hash;
            return ;
        }


        // best price
        if((is_sell  && queue.elems[queue.start].order.baseAmount > baseAmount) ||
           (!is_sell && queue.elems[queue.start].order.baseAmount < baseAmount))
        {
            queue.elems[od_hash].next = queue.start;
            queue.start = od_hash;
            return ;
        }

        // worst price
        if((is_sell  && queue.elems[queue.end].order.baseAmount < baseAmount) ||
           (!is_sell && queue.elems[queue.end].order.baseAmount > baseAmount))
        {
            queue.elems[queue.end].next = od_hash;
            queue.end = od_hash;
            return ;
        }

        // middle price
        uint256 odh = queue.start;
        uint256 next = queue.elems[odh].next;
        while(next != 0)
        {
            if((is_sell  && queue.elems[next].order.baseAmount > baseAmount) ||
               (!is_sell && queue.elems[next].order.baseAmount < baseAmount))
                break;

            odh = next;
            next = queue.elems[odh].next;
        }
        queue.elems[od_hash].next = next;
        queue.elems[odh].next = od_hash;
    }

    // remove sell/buy queue
    // returns baseAmount, quoteAmount
    function remove_queue(Queue storage queue, uint256 od_hash)
        internal
    {
        // empty queue
        if (queue.start == 0 &&
            queue.end == 0)
        {
            return ;
        }

        // best price
        if(queue.start == od_hash)
        {
            queue.start = queue.elems[od_hash].next;
            delete queue.elems[od_hash];
            return ;
        }

        // middle/worst price
        uint256 odh = queue.start;
        uint256 next = queue.elems[odh].next;
        while(next != 0)
        {
            if(next == od_hash)
                break;

            odh = next;
            next = queue.elems[odh].next;
        }
        queue.elems[odh].next = queue.elems[od_hash].next;
        delete queue.elems[od_hash];
    }

}
