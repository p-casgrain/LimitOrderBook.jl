# LimitOrderBook

[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://p-casgrain.github.io/LimitOrderBook.jl/dev/)
[![CI](https://github.com/p-casgrain/LimitOrderBook.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/p-casgrain/LimitOrderBook.jl/actions/workflows/CI.yml)
[![GitHub issues](https://img.shields.io/github/issues/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/issues)
[![GitHub forks](https://img.shields.io/github/forks/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/network)
[![GitHub license](https://img.shields.io/github/license/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/blob/main/LICENSE)
<!-- [![Coverage](https://codecov.io/gh/p-casgrain/LimitOrderBook.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/p-casgrain@github.com/LimitOrderBook.jl) -->

## About
`LimitOrderBook.jl` is a [limit order book](https://en.wikipedia.org/wiki/Order_book) (LOB) matching engine written in Julia, intended to be used for back-testing and simulation. The package implements a price-time priority LOB using an AVL Tree based implementations in line with the implementations proposed by [Jenq \& Jenq, 2018](https://csce.ucmss.com/cr/books/2018/LFS/CSREA2018/FCS3665.pdf) and [He et al., 2017](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf). 

At this time, the package is lightweight and only includes relatively basic matching functionality, though additional features may be added in the future.
The package does not yet include any speed benchmarks, though it should allow around 1-5 million inserts per second on average depending on the hardware.

__The package is still a work in progress and may still have some bugs.__

## Documentation

The `OrderBook` object is a data structure containing `Order`s. The package includes the functions `submit_limit_order!`, `cancel_order!` and `submit_market_order!` to insert and remove orders, as well as `book_depth_info`, `volume_bid_ask`, `best_bid_ask`, `n_orders_bid_ask`and `get_acct` to return order book statistics and information. The utility function `write_csv` writes the entire book to an IO stream in `csv` format to save its state. The package also includes `print`ing facilities to display the book status in the console. See the documentation, example and tests for more details.

### Installation

``````julia
Pkg.add(url="https://github.com/p-casgrain/LimitOrderBook.jl")
``````

### Examples

A simple example is provided below.

````````````julia
    using LimitOrderBook
    MyLOBType = OrderBook{Int64,Float32,Int64,Int64} # define LOB type
    ob = MyLOBType() # initialize order book

    # fill book with random limit orders
    randspread() = ceil(-0.05*log(rand()),digits=2)
    rand_side() = rand([BUY_ORDER,SELL_ORDER])
    for i=1:1000
        # add some limit orders
        submit_limit_order!(ob,2i,BUY_ORDER,99.0-randspread(),rand(5:5:20))
        submit_limit_order!(ob,3i,SELL_ORDER,99.0+randspread(),rand(5:5:20))
        if (rand() < 0.1) # and some market orders
            submit_market_order!(ob,rand_side(),rand(10:25:150))
        end
    end

    submit_limit_order!(ob,111,SELL_ORDER,99.05,10) # submit an order
    cancel_order!(ob,111,SELL_ORDER,99.05) # now cancel it

    ob # show state of the book
````````````

