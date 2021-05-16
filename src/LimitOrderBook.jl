module LimitOrderBook
    include("util.jl")
    include("orderqueue.jl")
    include("onesidebook.jl")
    include("book.jl")
    export OrderBook, Order, submit_limit_order!, cancel_limit_order!, 
        submit_market_order!, get_book_info
end
