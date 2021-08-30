using UnicodePlots: barplot
using Base: show, print, popfirst!


"""
    AcctMap{Oid,Aid,ST,PT}

Collection of open orders by account. 

`{Oid,Aid,ST,PT}` characterize the type of Order present in the `AcctMap`. 
See documentation on [`Order`](@ref) for more information on these types.

The account map has the structure of a nested `Dict`.
The outer key is the account id, mapping to an `AVLTree` of `Order`s keyed by order id.
"""
AcctMap{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real} = Dict{Aid,AVLTree{Oid,Order{Oid,Aid,ST,PT}}}


"""
    OrderBook{Oid,Aid,ST,PT}

An `OrderBook` is a data structure containing __limit orders__ represented as objects of type `Order{Oid,Aid,ST,PT}`.

See documentation on [`Order`](@ref) for more information on the parametric type `Order{Oid,Aid,ST,PT}`.

How to use `Orderbook`:
 - Initialize an empty limit order book as `OrderBook{Oid,Aid,ST,PT}()`
 - __Submit__ or __cancel__ limit orders with [`submit_limit_order!`](@ref) and [`cancel_limit_order!`](@ref). 
 - Submit __market orders__ with [`submit_market_order!`](@ref)
 - Retrieve order book state information with `print` or `show` methods, as well as [`book_depth_info`](@ref), [`best_bid_ask`](@ref), [`volume_bid_ask`](@ref), [`n_orders_bid_ask`](@ref) and [`get_acct`](@ref)
 - Write book state to `csv` file with [`write_csv`](@ref).

"""
@kwdef mutable struct OrderBook{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
    bid_orders::OneSidedBook{Oid,Aid,ST,PT} = OneSidedBook{Oid,Aid,ST,PT}(side = :BID) # bid orders
    ask_orders::OneSidedBook{Oid,Aid,ST,PT} = OneSidedBook{Oid,Aid,ST,PT}(side = :ASK) # ask orders
    acct_map::AcctMap{Oid,Aid,ST,PT} = AcctMap{Oid,Aid,ST,PT}() # Map from acct_id::Aid to AVLTree{order_id::Oid,Order{Oid,Aid,ST,PT}}
    flags = Dict{Symbol,Bool}() # container for additional order book logic flags (not yet implemented)
end



## Limit Order Submission and Cancellation functions

@inline function _add_order_acct_map!(
    acct_map::AcctMap{Oid,Aid,ST,PT},
    acct::Union{Aid,Nothing},
    order::Order{Oid,Aid,ST,PT},
) where {Oid,Aid,ST,PT}
    if !isnothing(acct)
        if !haskey(acct_map, acct)
            acct_map[acct] = AVLTree{Oid,Order{Oid,Aid,ST,PT}}() # If account isn't registered, register
        end
        insert!(acct_map[acct], order.orderid, order) # Add order to account map
    end
end

@inline function _delete_order_acct_map!(
    acct_map,
    acct::Union{Aid,Nothing},
    orderid::Oid,
) where {Oid,Aid,ST,PT}
    if !isnothing(acct)
        !haskey(acct_map, acct) ? nothing : delete!(acct_map[acct], orderid)
    end
end


"""
    submit_limit_order!(ob::OrderBook, orderid, price, size, side [, acct_id=nothing])

Enter limit order with matching properties into `ob::OrderBook`. 

If `acct_id` provided, account holdings are tracked in `ob.AcctMap`.
"""
function submit_limit_order!(
    ob::OrderBook{Oid,Aid,ST,PT},
    orderid::Oid,
    price::Real,
    size::Real,
    side::Symbol,
    acct_id::Union{Nothing,Aid} = nothing,
) where {Oid,Aid,ST,PT}
    side in (:BID, :ASK) || error("invalid trade side argument") # check valid side
    # check that price in right range
    best_bid, best_ask = best_bid_ask(ob)
    (side==:BID) && !isnothing(best_ask) && (price>=best_ask) && error(":BID LO must have price < best ask price")
    (side==:ASK) && !isnothing(best_bid) && (price<=best_bid) && error(":ASK LO must have price > best bid price")
    # create order object
    ord = Order{Oid,Aid,ST,PT}(orderid, side, size, price, acct_id)
    # Add actual order to the correct OneSideBook
    ord.side == :ASK ? insert_order!(ob.ask_orders, ord) : insert_order!(ob.bid_orders, ord)
    # Update account map
    _add_order_acct_map!(ob.acct_map, acct_id, ord)
    return ord
end


"""
    cancel_limit_order!(ob::OrderBook, orderid, price, side [, acct_id=nothing])

Cancels order with matching information from OrderBook.

Provide `acct_id` if known to guarantee correct account tracking.
"""
function cancel_limit_order!(
    ob::OrderBook{Oid,Aid,ST,PT},
    orderid,
    price,
    side::Symbol
) where {Oid,Aid,ST,PT}
    side in (:BID, :ASK) || error("invalid trade side argument") # check valid side
    # Delete order from bid or ask book
    popped_ord = (side == :ASK) ? pop_order!(ob.ask_orders, PT(price), Oid(orderid)) :
    pop_order!(ob.bid_orders, PT(price), Oid(orderid))
    # Delete order from account maps
    if !isnothing(popped_ord) && !isnothing(popped_ord.acctid)
        _delete_order_acct_map!(ob.acct_map, popped_ord.acctid, popped_ord.orderid)
    end
    return popped_ord
end

"""
    cancel_limit_order!(ob::OrderBook, o::Order)

Cancels order `o::Order` from LimitOrderBook.
"""
cancel_limit_order!(ob::OrderBook, o::Order) = cancel_limit_order!(ob,o.orderid,o.price,o.side)

## Market Order insertion functions

"""
    Fill market order by walking the book using Price/Arrival priority
"""
@inline function _submit_market_order!(sb::OneSidedBook{Oid,Aid,ST,PT}, mo_size::ST) where {Oid,Aid,ST,PT}
    mo_size > 0 || error("market order size must be positive")
    order_match_lst = Vector{Order}()
    left_to_trade = mo_size # remaining quantity to trade
    while !isempty(sb.book) && (left_to_trade > 0)
        price_queue::OrderQueue = popfirst!(sb.book)
        if price_queue.total_volume[] <= left_to_trade # If entire queue is to be wiped out
            append!(order_match_lst, price_queue.queue) # Add all of the orders to the match list
            left_to_trade -= price_queue.total_volume[] # decrement what's left to trade
            # Update stats
            sb.num_orders -= price_queue.num_orders[]
            sb.total_volume -= price_queue.total_volume[]
        else
            while !isempty(price_queue) && (left_to_trade > 0)
                best_ord::Order = popfirst!(price_queue) # pop out best order
                if left_to_trade >= best_ord.size # Case 1: Limit order gets wiped out
                    # Add best_order to match list & decrement outstanding MO
                    push!(order_match_lst, best_ord)
                    left_to_trade -= best_ord.size
                    # Update book stats - n_orders & volume
                    sb.total_volume -= best_ord.size
                    sb.num_orders -= 1
                else
                    left_to_trade < best_ord.size # Case 2: Market Order gets wiped out
                    # Return the difference: LO.size-MO.size back to the order book
                    return_ord = copy_modify_size(best_ord, best_ord.size - left_to_trade)
                    pushfirst!(price_queue, return_ord)
                    # Add remainder to match list & decrement outstanding MO
                    best_ord = copy_modify_size(best_ord, left_to_trade)
                    push!(order_match_lst, best_ord)
                    left_to_trade -= best_ord.size
                    # Update book stats - only volume, since we placed an order back
                    sb.total_volume -= best_ord.size
                end
            end
            if !isempty(price_queue) # If price queue wasn't killed, put it back into the OneSideBook
                price_key = (sb.side == :ASK) ? price_queue.price : -price_queue.price
                insert!(sb.book, price_key, price_queue)
            end
        end
    end
    # Update Sidebook statistics
    _update_next_best_price!(sb)
    # Return results
    return order_match_lst, left_to_trade
end



"""
    submit_market_order!(ob::OrderBook{Oid,Aid,ST,PT},side::Symbol,mo_size) 

Submit market order to `OrderBook` on given side (`:ASK` or `:BID`) and size `mo_size`.

Market orders are filled by price-time priority.

Returns tuple `( ord_lst::Vector{Order}, complete_status::Symbol, left_to_trade::ST )`
where
 - `ord_lst` is a list of _limit orders_ that _market order_ matched with
 - `left_to_trade` is the remaining size of un-filled order ( `==0` if order is complete, `>0` if incomplete)

"""
function submit_market_order!(ob::OrderBook{Oid,Aid,ST,PT}, side::Symbol, mo_size) where {Oid,Aid,ST,PT}
    side ∈ (:BID, :ASK) || error("invalid trade side provided") # check valid side
    if side == :ASK
        return _submit_market_order!(ob.ask_orders, ST(mo_size))
    else
        return _submit_market_order!(ob.bid_orders, ST(mo_size))
    end
end

## Utility functions

"""
    order_types(::X{Oid,Aid,ST,PT})

Return parametric types of either an `Order`, `OrderQueue`, `OneSidedbook` or `OrderBook`.

# Example
```
order_types(Order{Int64,Int64,Int64,Float64}) = (Int64,Int64,Int64,Float64)
```

"""
order_types(::Order{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid,Aid,ST,PT
order_types(::OrderQueue{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid,Aid,ST,PT
order_types(::OneSidedBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid,Aid,ST,PT
order_types(::OrderBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid,Aid,ST,PT



## Order book statistics functions

@inline function _sidebook_stats(sb::OneSidedBook, max_depth)
    # get book statistics until fixed price depth
    raw_info_list = [
        (pq.price[], pq.total_volume[], pq.num_orders[]) for
        (pk, pq) in Base.Iterators.take(sb.book, max_depth)
    ]
    # Compile and return as dict of vectors
    return Dict(
        :side => sb.side,
        :price => [x[1] for x in raw_info_list],
        :volume => [x[2] for x in raw_info_list],
        :orders => [x[3] for x in raw_info_list],
    )
end

"""
    book_depth_info(ob::OrderBook; max_depth=5)

Returns prices, volumes and order counts at bid and ask in `ob::OrderBook` 
until fixed depth `max_depth` as a nested `Dict`.
"""
function book_depth_info(ob::OrderBook; max_depth = 5)
    return Dict(
        :BID => _sidebook_stats(ob.bid_orders, max_depth),
        :ASK => _sidebook_stats(ob.ask_orders, max_depth),
    )
end

"""
    best_bid_ask(ob::OrderBook)

Return best bid/ask prices in order book as a `Tuple`
"""
best_bid_ask(ob::OrderBook) = (ob.bid_orders.best_price, ob.ask_orders.best_price)

"""
    volume_bid_ask(ob::OrderBook)

Return total bid and ask volume from order book as a `Tuple`.
"""
volume_bid_ask(ob::OrderBook) = (ob.bid_orders.total_volume, ob.ask_orders.total_volume)

"""
    n_orders_bid_ask(ob::OrderBook)

Return total number of orders on each side of order book, returned as a `Tuple`
"""
n_orders_bid_ask(ob::OrderBook) = (ob.bid_orders.num_orders, ob.ask_orders.num_orders)


"""
    get_acct(ob::OrderBook{Oid,Aid,ST,PT},acct_id::Aid)

Return all open orders assigned to account `acct_id`
"""
get_acct(ob::OrderBook{Oid,Aid,ST,PT}, acct_id::Aid) where {Oid,Aid,ST,PT} = get(ob.acct_map,acct_id,nothing)


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
    io::IO,
    ob::OrderBook;
    row_formatter = _order_to_csv,
    header = "TRD,ID,SIDE,SIZE,PX,ACCT",
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


@inline function _print_book_barplot(io::IO, ob::OrderBook{Oid,Aid,ST,PT}; max_depth = 5) where {Oid,Aid,ST,PT}
    # Get book info
    sb_info = LimitOrderBook.book_depth_info(ob, max_depth = max_depth)
    all_prices = [sb_info[:BID][:price]; sb_info[:ASK][:price]]
    
    println(io,"\n Order Book shape (within $max_depth ticks of center)")

    if !isempty(sb_info[:BID][:volume])
        # Get max price str length
        max_len = string.(all_prices) .|> length |> maximum

        bid_plt = barplot(
            lpad.(string.(reverse(sb_info[:BID][:price])), max_len, " "),
            reverse(sb_info[:BID][:volume]),
            color = :red,
            ylabel = ":BID",
            border = :none,
            padding = 0,
        )

        println(io, bid_plt)
    else
        print(io,"\n    :BID   <empty>\n")
    end

    if !isempty(sb_info[:ASK][:volume])
        # Get max price str length
        max_len = string.(all_prices) .|> length |> maximum

        ask_plt = barplot(
            lpad.(string.(sb_info[:ASK][:price]), max_len, " "),
            sb_info[:ASK][:volume],
            ylabel = ":ASK",
            border = :none,
            padding = 0,
        )

        println(io, ask_plt)
    else
        print(io,"\n    :ASK   <empty>\n")
    end

    return
end

function _print_book_info(io::IO,ob::OrderBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT}
    return print(io, 
            "OrderBook{Oid=$Oid,Aid=$Aid,ST=$ST,PT=$PT} with properties:\n",
            "  ⋄ best bid/ask price: $(best_bid_ask(ob))\n",
            "  ⋄ total bid/ask volume: $(volume_bid_ask(ob))\n",
            "  ⋄ total bid/ask orders: $(n_orders_bid_ask(ob))\n",
            "  ⋄ flags = $(ob.flags)")
end

Base.print(io::IO, ob::OrderBook) = _print_book_info(io,ob)

function Base.show(io::IO, ::MIME"text/plain", ob::OrderBook; max_depth = 5)
    println(io,ob)
    _print_book_barplot(io, ob; max_depth = max_depth)
    return 
end

