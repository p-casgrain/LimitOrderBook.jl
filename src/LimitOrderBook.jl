module LimitOrderBook
using AVLTrees
using Base: @kwdef
using Printf
include("orderqueue.jl")
include("sidebook.jl")
include("book.jl")
include("ordermatching.jl")
export BUY_ORDER, SELL_ORDER, VANILLA_FILLTYPE, IMMEDIATEORCANCEL_FILLTYPE, FILLORKILL_ORDER
export OrderBook, Order, OrderTraits, AcctMap, OrderSide
export submit_order!,
    submit_limit_order!,
    cancel_order!,
    submit_market_order!,
    submit_market_order_byfunds!,
    book_depth_info,
    volume_bid_ask,
    best_bid_ask,
    n_orders_bid_ask,
    ask_orders,
    bid_orders,
    get_acct,
    write_csv,
    order_types
end
