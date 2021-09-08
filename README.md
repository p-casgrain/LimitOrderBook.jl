# LimitOrderBook

[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://p-casgrain.github.io/LimitOrderBook.jl/dev/)
[![CI](https://github.com/p-casgrain/LimitOrderBook.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/p-casgrain/LimitOrderBook.jl/actions/workflows/CI.yml)
[![GitHub issues](https://img.shields.io/github/issues/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/issues)
[![GitHub forks](https://img.shields.io/github/forks/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/network)
[![GitHub license](https://img.shields.io/github/license/p-casgrain/LimitOrderBook.jl)](https://github.com/p-casgrain/LimitOrderBook.jl/blob/main/LICENSE)
<!-- [![Coverage](https://codecov.io/gh/p-casgrain/LimitOrderBook.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/p-casgrain@github.com/LimitOrderBook.jl) -->

## About
`LimitOrderBook.jl` is a [limit order book](https://en.wikipedia.org/wiki/Order_book) (LOB) matching engine written in Julia, intended to be used for backtesting of trading strategies and for simulation. The package implements a price-time priority LOB using an AVL Tree based implemetations in line with the implementations proposed by [Jenq \& Jenq, 2018](https://csce.ucmss.com/cr/books/2018/LFS/CSREA2018/FCS3665.pdf) and [He et al., 2017](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf). At this time, the package is lightweight and only includes basic matching functionality, though additional features may be added in the future.

The package does not yet include any speed benchmarks, though it should be relatively fast. __The package is still a work in progress and may still have some bugs.__

## Documentation

The most basic atomic type is the `Order` which contains information about its side, quantity, price, order-id and account-id. The `OrderBook` object is a data structure containing `Order`s. The package includes the functions `submit_limit_order!`, `cancel_limit_order!` and `submit_market_order!` to insert and remove orders, as well as `book_depth_info`, `volume_bid_ask`, `best_bid_ask`, `n_orders_bid_ask`and `get_acct` to return order book statistics and information. The utility function `write_csv` writes the entire book to an IO stream in csv format to save its state. The package also includes `print`ing facilities to display the book status in the console. See the included documentation and example for more details.

### Installation

``````julia
Pkg.add(url="https://github.com/p-casgrain/LimitOrderBook.jl")
``````

### Examples

A simple example is provided below to demonstrate example uses of the package.

````````````julia

````````````

