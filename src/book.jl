using UnicodePlots: barplot
using Base: show, print, popfirst!

"""
    AcctMap{Sz,Px,Oid,Aid}

Collection of open orders by account. 

`{Sz,Px,Oid,Aid}` characterize the type of Order present in the `AcctMap`. 
See documentation on [`Order`](@ref) for more information on these types.

The account map has the structure of a nested `Dict`.
The outer key is the account id, mapping to an `AVLTree` of `Order`s keyed by order id.
"""
AcctMap{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer} = Dict{
    Aid,AVLTree{Oid,Order{Sz,Px,Oid,Aid}}
}

# Add functions for adding and removing orders from account map
@inline function _add_order_acct_map!(
    acct_map::AcctMap{Sz,Px,Oid,Aid}, acct::Aid, order::Order{Sz,Px,Oid,Aid}
) where {Sz,Px,Oid,Aid}
    if !haskey(acct_map, acct)
        acct_map[acct] = AVLTree{Oid,Order{Sz,Px,Oid,Aid}}() # If account isn't registered, register
    end
    insert!(acct_map[acct], order.orderid, order) # Add order to account map
    return nothing
end

@inline function _delete_order_acct_map!(
    acct_map::AcctMap{Sz,Px,Oid,Aid}, acct::Aid, orderid::Oid
) where {Sz,Px,Oid,Aid}
    haskey(acct_map, acct) && delete!(acct_map[acct], orderid)
    return nothing
end

"""
    OrderBook{Sz,Px,Oid,Aid}

An `OrderBook` is a data structure containing __limit orders__ represented as objects of type `Order{Sz,Px,Oid,Aid}`.

See documentation on [`Order`](@ref) for more information on the parametric type `Order{Sz,Px,Oid,Aid}`.

How to use `Orderbook`:
 - Initialize an empty limit order book as `OrderBook{Sz,Px,Oid,Aid}()`
 - __Submit__ or __cancel__ limit orders with [`submit_limit_order!`](@ref) and [`cancel_order!`](@ref). 
 - Submit __market orders__ with [`submit_market_order!`](@ref)
 - Retrieve order book state information with `print` or `show` methods, as well as [`book_depth_info`](@ref), [`best_bid_ask`](@ref), [`volume_bid_ask`](@ref), [`n_orders_bid_ask`](@ref) and [`get_acct`](@ref)
 - Write book state to `csv` file with [`write_csv`](@ref).

"""
mutable struct OrderBook{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}
    bid_orders::OneSidedBook{Sz,Px,Oid,Aid} # bid orders
    ask_orders::OneSidedBook{Sz,Px,Oid,Aid} # ask orders
    acct_map::AcctMap{Sz,Px,Oid,Aid} # Map from acct_id::Aid to AVLTree{order_id::Oid,Order{Sz,Px,Oid,Aid}}
    flags::Dict{Symbol,Any} # container for additional order book logic flags (not yet implemented)
    function OrderBook{Sz,Px,Oid,Aid}() where {Sz,Px,Oid,Aid}
        return new{Sz,Px,Oid,Aid}(
            OneSidedBook{Sz,Px,Oid,Aid}(; is_bid_side=true),
            OneSidedBook{Sz,Px,Oid,Aid}(; is_bid_side=false),
            AcctMap{Sz,Px,Oid,Aid}(),
            Dict{Symbol,Any}(:PlotTickMax => 5),
        )
    end
end

"""
    clear_book!(ob::OrderBook,n_keep::Int64=10)

Remove all orders beyond `n_keep ≥ 0` from the best bid and best ask.
When `n_keep==0`, all orders are cleared.

"""
function clear_book!(ob::OrderBook{Sz,Px,Oid,Aid}, n_keep::Int64=10) where {Sz,Px,Oid,Aid}
    (n_keep < 0) && error("$n_keep should be non-negative")
    # clear the bids
    cleared_bids = Vector{Order{Sz,Px,Oid,Aid}}()
    bids_to_clear = [abs(k) for (k, v) in ob.bid_orders.book]
    bids_to_clear = x -> last(x, max(length(x) - n_keep, 0))(bids_to_clear) # clear all but last n
    for px in bids_to_clear
        cleared_queue = _popat_queue!(ob.bid_orders, px)
        append!(cleared_bids, cleared_queue.queue)
    end
    # clear the asks
    cleared_asks = Vector{Order{Sz,Px,Oid,Aid}}()
    asks_to_clear = [abs(k) for (k, v) in ob.ask_orders.book]
    asks_to_clear = x -> first(x, max(length(x) - n_keep, 0))(asks_to_clear) # clear all but last n
    for px in asks_to_clear
        cleared_queue = _popat_queue!(ob.ask_orders, px)
        append!(cleared_asks, cleared_queue.queue)
    end
    return cleared_bids, cleared_asks
end

## Order book statistics functions

@inline function _sidebook_stats(sb::OneSidedBook, max_depth)
    # get book statistics until fixed price depth
    raw_info_list = [
        (pq.price[], pq.total_volume[], pq.num_orders[]) for
        (pk, pq) in Base.Iterators.take(sb.book, max_depth)
    ]
    # Compile and return as dict of vectors
    return Dict(
        :side => isbidbook(sb) ? :BID : :ASK,
        :price => [x[1] for x in raw_info_list],
        :volume => [x[2] for x in raw_info_list],
        :orders => [x[3] for x in raw_info_list],
    )
end

"""
    book_depth_info(ob::OrderBook, max_depth=5)

Returns prices, volumes and order counts at bid and ask in `ob::OrderBook` 
until fixed depth `max_depth` as a nested `Dict`.
"""
function book_depth_info(ob::OrderBook, max_depth=5)
    return Dict(
        :BID => _sidebook_stats(ob.bid_orders, max_depth),
        :ASK => _sidebook_stats(ob.ask_orders, max_depth),
    )
end

"""
    best_bid_ask(ob::OrderBook)

Return best bid/ask prices in order book as a `Tuple`
"""
function best_bid_ask(ob::OrderBook{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    return (
        ob.bid_orders.best_price::Union{Nothing,Px},
        ob.ask_orders.best_price::Union{Nothing,Px},
    )
end

"""
    volume_bid_ask(ob::OrderBook)

Return total bid and ask volume from order book as a `Tuple`.
"""
function volume_bid_ask(ob::OrderBook{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    return (
        ob.bid_orders.total_volume::Union{Nothing,Sz},
        ob.ask_orders.total_volume::Union{Nothing,Sz},
    )
end

"""
    n_orders_bid_ask(ob::OrderBook)

Return total number of orders on each side of order book, returned as a `Tuple`
"""
function n_orders_bid_ask(ob::OrderBook)
    return (
        ob.bid_orders.num_orders::Union{Nothing,Int32},
        ob.ask_orders.num_orders::Union{Nothing,Int32},
    )
end

# Order Book utility functions

"""
    order_types(::Order{Sz,Px,Oid,Aid})
    order_types(::OneSidedBook{Sz,Px,Oid,Aid})
    order_types(::OrderBook{Sz,Px,Oid,Aid})

Return parametric types of either an `Order`, `OrderQueue`, `OneSidedbook` or `OrderBook`.
"""
order_types(::Order{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid} = Sz, Px, Oid, Aid
order_types(::OneSidedBook{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid} = Sz, Px, Oid, Aid
order_types(::OrderBook{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid} = Sz, Px, Oid, Aid

"""
    get_acct(ob::OrderBook{Sz,Px,Oid,Aid},acct_id::Aid)

Return all open orders assigned to account `acct_id`
"""
function get_acct(ob::OrderBook{Sz,Px,Oid,Aid}, acct_id::Aid) where {Sz,Px,Oid,Aid}
    return get(ob.acct_map, acct_id, nothing)
end


"""
    ask_orders(sb::OneSidedBook)

Return an iterator over all __ask orders__ by price/time priority.
"""
ask_orders(ob::OrderBook) = Iterators.flatten(q for (k,q) in ob.ask_orders.book)

"""
    bid_orders(sb::OneSidedBook)

Return an iterator over all __bid orders__ by price/time priority.
"""
bid_orders(ob::OrderBook) = Iterators.flatten(q for (k,q) in ob.bid_orders.book)


"""
    write_csv(
        io::IO,
        ob::OrderBook;
        row_formatter = _order_to_csv,
        header = "TRD,ID,SIDE,SIZE,PX,ACCT",
        )

Write OrderBook `ob` to an IO stream into `csv` format where each row corresponds to an order
The formatting for each row is given by the function argument `row_formatter(::Order)::String`.
The `csv` header can be provided as an argument where setting it to `nothing` writes no header.
"""
function write_csv(
    io::IO, ob::OrderBook; row_formatter=_order_to_csv, header="TRD,ID,SIDE,SIZE,PX,ACCT"
)
    cnt = 0
    !is_nothing(write_header) && (cnt += write(io, header, '\n'))
    # write all of the bids
    for (pk, pq) in ob.bid_orders.book
        for ord in pq.queue
            cnt += write(io, _order_to_csv(ord), '\n')
        end
    end
    # write all of the asks
    for (pk, pq) in ob.ask_orders.book
        for ord in pq.queue
            cnt += write(io, _order_to_csv(ord) * '\n')
        end
    end
    return cnt
end

@inline function _print_book_barplot(
    io::IO, ob::OrderBook{Sz,Px,Oid,Aid}
) where {Sz,Px,Oid,Aid}
    # Get book info
    max_depth = ob.flags[:PlotTickMax]
    sb_info = LimitOrderBook.book_depth_info(ob, max_depth)
    all_prices = [sb_info[:BID][:price]; sb_info[:ASK][:price]]

    println(io, "\n Order Book histogram (within $max_depth ticks of center):\n")

    if !isempty(sb_info[:BID][:volume])
        # Get max price str length
        max_len = maximum(length(string.(all_prices)))

        bid_plt = barplot(
            lpad.(string.(reverse(sb_info[:BID][:price])), max_len, " "),
            reverse(sb_info[:BID][:volume]);
            color=:red,
            ylabel=":BID",
            border=:none,
            padding=0,
        )

        println(io, bid_plt, '\n')
    else
        print(io, "\n    :BID   <empty>\n")
    end

    if !isempty(sb_info[:ASK][:volume])
        # Get max price str length
        max_len = maximum(length(string.(all_prices)))

        ask_plt = barplot(
            lpad.(string.(sb_info[:ASK][:price]), max_len, " "),
            sb_info[:ASK][:volume];
            ylabel=":ASK",
            border=:none,
            padding=0,
        )

        println(io, ask_plt)
    else
        print(io, "\n    :ASK   <empty>\n")
    end

    return nothing
end

function _print_book_info(io::IO, ob::OrderBook{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    return print(
        io,
        "OrderBook{Sz=$Sz,Px=$Px,Oid=$Oid,Aid=$Aid} with properties:\n",
        "  ⋄ best bid/ask price: $(best_bid_ask(ob))\n",
        "  ⋄ total bid/ask volume: $(volume_bid_ask(ob))\n",
        "  ⋄ total bid/ask orders: $(n_orders_bid_ask(ob))\n",
        "  ⋄ flags = $([ k => v for (k,v) in ob.flags])",
    )
end

Base.print(io::IO, ob::OrderBook) = _print_book_info(io, ob)

function Base.show(io::IO, ::MIME"text/plain", ob::OrderBook)
    println(io, ob)
    _print_book_barplot(io, ob)
    return nothing
end

function Base.show(io::IO, ob::OrderBook)
    println(io, ob)
    return nothing
end
