# free dex
这个项目的目标是：  
#### 只要以太坊能访问，任务人均可自由地进行兑换

本智能合约基于hydro的代码，增加了order 函数直接支持链上订单撮合，实现目标：
- 彻底解决cancel订单有可能被恶意利用的风险
- 取消原有合约的approve的白名单机制，彻底防止链下作恶的风险
- 取消上币概念，任何人都可以提交任何token对base的交易对请求
- 实现钱包的兑换功能的无服务端工作方式