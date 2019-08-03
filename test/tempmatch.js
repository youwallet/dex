

var TempMatch = artifacts.require("./TempMatch.sol");

const { latestTime } = require("./utils/latestTime.js");
const { increaseTime } = require("./utils/increaseTime.js");
var log4js = require('log4js');

contract("beginning to test TempMatch", accounts => {

    const [sender, owner, proxy, dex, acc1, acc2, acc3] = accounts;
    const MAGNITUDE = 10 ** 18;
    const DAY = 3600 * 24;

    var logger = log4js.getLogger();
    logger.level = 'info';

    let time;

    /*
     * 所有case之前都要执行的内容:
     * 1. 生成新的合约
     * 2. 获取最新块的时间
     */
    beforeEach(async() => {
        tm = await TempMatch.new(proxy, dex);
        time = await latestTime();
    });

    it("case 1", async() => {

    });
})
