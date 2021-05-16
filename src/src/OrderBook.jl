"""
Orderbook.jl is a simple implementation of a price-time priority order book.
"""
module OrderBook  
    include("./orderbook/util.jl")
    include("./orderbook/orderqueue.jl")
    include("./orderbook/onesidebook.jl")
    include("./orderbook/orderbook.jl")

    export OrderBook, Order, OrderQueue,
           submit_limit_order!, cancel_limit_order!, submit_market_order!,
           book_depth_info, best_bid_ask, volume_bid_ask, n_orders_bid_ask,
           list_account_orders

end