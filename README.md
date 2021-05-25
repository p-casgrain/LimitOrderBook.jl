# LimitOrderBook

[![Coverage](https://codecov.io/gh/p-casgrain@github.com/LimitOrderBook.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/p-casgrain@github.com/LimitOrderBook.jl)

`LimitOrderBook.jl` is a [limit order book](https://en.wikipedia.org/wiki/Order_book) (LOB) matching engine written in Julia, intended to be used for backtesting of trading strategies and for simulation. The package implements a price-time priority LOB using AVL Tree based implemetations in line with the implementations proposed by [Jenq \& Jenq, 2018](https://csce.ucmss.com/cr/books/2018/LFS/CSREA2018/FCS3665.pdf) and [He et al., 2017](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf). At this time, the package is lightweight and only includes only basic matching functionality, though additional features may be added in the future. The package does not yet include any speed benchmarks, though it should be relatively fast.

### Documentation

The most basic atomic type is the `Order` which contains information about its side, quantity, price, order id and account id. The `OrderBook` object is a data structure containing `Order`s. The package includes the functions `submit_limit_order!`, `cancel_limit_order!` and `submit_market_order!` to insert and remove orders, as well as `book_depth_info`, `volume_bid_ask`, `best_bid_ask`, `n_orders_bid_ask`and `get_acct` to return order book statistics and information. The utility function `write_csv` writes the entire book to an IO stream in csv format to save its state. The package also includes `print`ing facilities to display the book status in the console.

### Examples

A simple example is provided below to demonstrate some of the package functionality.

````````````julia
using LimitOrderBook

begin # Create (Deterministic) Limit Order Generator
    using Base.Iterators: cycle, take, zip, flatten
    orderid_iter = Base.Iterators.countfrom(1)
    sign_iter = cycle([1,-1,-1,1,1,-1])
    side_iter = ( s>0 ? :ASK : :BID for s in sign_iter )
    spread_iter = cycle([3 2 2 3 2 3 4 2 2 3 2 3 2 3 3 2 5 6 4 2 5 2 2 2]*1e-2)
    price_iter = ( Float32(100.0 + sgn*δ) for (δ,sgn) in zip(spread_iter,sign_iter) )
    size_iter = cycle([2,5,3,4,10,15,1,6,13,11,4,1,5])
    # zip them all together
    lmt_order_info_iter = zip(orderid_iter,price_iter,size_iter,side_iter)
end

begin # Create (Deterministic) Market Order Generator
    mkt_size_iter = cycle([10,20,30,15,25,5,7])
    mkt_side_iter = cycle([:BID,:ASK,:ASK,:BID,:ASK,:BID])
    mkt_order_info_iter = zip(mkt_size_iter,mkt_side_iter)
end

begin
    ob = LimitOrderBook.OrderBook() #Initialize empty book
    order_info_lst = take(lmt_order_info_iter,50000) # grab 50k limit orders
  
    # Add add all LOs to the book
    for (orderid, price, size, side) in order_info_lst
        LimitOrderBook.submit_limit_order!(ob,orderid,price,size,side,acct_id=10101)
    end
    # Cancel them all
    for (orderid, price, size, side) in order_info_lst
        LimitOrderBook.cancel_limit_order!(ob,orderid,price,side,acct_id=10101)
    end
end

begin
    # Add a more orders, then submit MO
    for (orderid, price, size, side) in Base.Iterators.take( lmt_order_info_iter, 500 )
        LimitOrderBook.submit_limit_order!(ob,orderid,price,size,side)
    end
    # MO returns matches and completion flag  
    mo_matches, mo_flag = LimitOrderBook.submit_market_order!(ob,:BID,100)
end


````````````

