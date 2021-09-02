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
AcctMap{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real} =
    Dict{Aid,AVLTree{Oid,Order{Oid,Aid,ST,PT}}}


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
    flags = Dict{Symbol,Any}(:LimitAutoCross => true,:PlotTickMax => 5) # container for additional order book logic flags (not yet implemented)
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
    _limit_order_cross!(ob::OrderBook{Oid,Aid,ST,PT},limit_price::PT,limit_size::ST)

Cross limit order with opposite side of book. Return matches and outstanding size.

"""
function _limit_order_cross!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    limit_price::PT,
    limit_size::ST,
) where {Oid,Aid,ST,PT}
    limit_size > 0 || error("cross size must be positive")
    order_match_lst = Vector{Order}()
    price_cmp = (sb.side == :BID) ? >=(limit_price) : <=(limit_price)
    left_to_trade = limit_size # remaining quantity to trade
    while !isempty(sb.book) &&
              (left_to_trade > 0) &&
              (price_cmp ∘ abs ∘ first ∘ first)(sb.book) # while book not empty, order not done and best price within limit price
        price_queue::OrderQueue = popfirst!(sb.book)
        if price_queue.total_volume[] <= left_to_trade # If entire queue is to be wiped out
            append!(order_match_lst, price_queue.queue) # Add all of the orders to the match list
            left_to_trade -= price_queue.total_volume[] # decrement what's left to trade
            # Update stats
            sb.num_orders -= price_queue.num_orders[]
            sb.total_volume -= price_queue.total_volume[]
        else
            while !isempty(price_queue) && (left_to_trade > 0) # while not done and queue not empty 
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
    submit_limit_order!(ob::OrderBook, orderid, price, size, side [, acct_id=nothing])

Enter limit order with matching properties into `ob::OrderBook`. Returns Order if successful, returns `nothing` and a warning in case of failiure.

If `acct_id` provided, account holdings are tracked in `ob.AcctMap`.
"""
function submit_limit_order!(
    ob::OrderBook{Oid,Aid,ST,PT},
    orderid::Oid,
    limit_price::Real,
    limit_size::Real,
    side::Symbol,
    acct_id::Union{Nothing,Aid} = nothing,
) where {Oid,Aid,ST,PT}
    side in (:BID, :ASK) || error("invalid trade side argument") # check valid side
    # check that price in right range
    best_bid, best_ask = best_bid_ask(ob)
    if (side == :BID) && !isnothing(best_ask) && (limit_price >= best_ask) # order is bid and crosses
        if !ob.flags[:LimitAutoCross]
            @warn(":BID LO should have price < best ask price. Order not processed")
            return nothing, Vector{Order{Oid,Aid,ST,PT}}()
        else
            match_lst, remaining_size =
                _limit_order_cross!(ob.ask_orders, PT(limit_price), ST(limit_size))
            # remaining_size>0 && error("myfakeerror")
        end
    elseif (side == :ASK) && !isnothing(best_bid) && (limit_price <= best_bid) # order is ask and crosses 
        if !ob.flags[:LimitAutoCross]
            @warn(":ASK LO should have price > best bid price. Order not processed")
            return nothing, Vector{Order{Oid,Aid,ST,PT}}()
        else
            match_lst, remaining_size =
                _limit_order_cross!(ob.bid_orders, PT(limit_price), ST(limit_size))
            # remaining_size>0 && error("myfakeerror")
        end
    else # order does not cross
        match_lst = Vector{Order{Oid,Aid,ST,PT}}()
        remaining_size = ST(limit_size)
    end

    if remaining_size > 0 # if there are remaining shares, add remaining to the LOB
        # create order object
        new_lmt_order =
            Order{Oid,Aid,ST,PT}(orderid, side, limit_size, limit_price, acct_id)
        # Add actual order to the correct OneSideBook
        new_lmt_order.side == :ASK ? insert_order!(ob.ask_orders, new_lmt_order) :
        insert_order!(ob.bid_orders, new_lmt_order)
        # Update account map
        _add_order_acct_map!(ob.acct_map, acct_id, new_lmt_order)
        # return new
        return new_lmt_order, match_lst
    else
        return nothing, Vector{Order{Oid,Aid,ST,PT}}()
    end
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
    side::Symbol,
) where {Oid,Aid,ST,PT}
    side in (:BID, :ASK) || error("invalid trade side argument") # check valid side
    # Delete order from bid or ask book
    popped_ord =
        (side == :ASK) ? pop_order!(ob.ask_orders, PT(price), Oid(orderid)) :
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
cancel_limit_order!(ob::OrderBook, o::Order) =
    cancel_limit_order!(ob, o.orderid, o.price, o.side)

## Market Order insertion functions

"""
    Fill market order by walking the book using Price/Arrival priority
"""
function _submit_market_order_bysize!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    mo_size::ST,
) where {Oid,Aid,ST,PT}
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
            while !isempty(price_queue) && (left_to_trade > 0) # while not done and queue not empty 
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
Fill market order by walking the book using Price/Arrival priority. 
__This version walks the book with funds rather than trade size.__
"""
function _submit_market_order_byfunds!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    funds::Real,
) where {Oid,Aid,ST,PT}
    funds > 0 || error("market order size must be positive")
    order_match_lst = Vector{Order}()
    funds_to_trade = funds # remaining quantity to trade
    while !isempty(sb.book) && (funds_to_trade > 0)
        price_queue::OrderQueue = popfirst!(sb.book)
        cur_price = price_queue.price # store queue price
        if (price_queue.total_volume[] * cur_price) <= funds_to_trade # If entire queue is to be wiped out
            append!(order_match_lst, price_queue.queue) # Add all of the orders to the match list
            funds_to_trade -= (price_queue.total_volume[] * cur_price) # decrement what's left to trade
            # Update stats
            sb.num_orders -= price_queue.num_orders[]
            sb.total_volume -= price_queue.total_volume[]
        else
            while !isempty(price_queue) && (funds_to_trade > 0) # while not done and queue not empty 
                best_ord::Order = popfirst!(price_queue) # pop out best order
                if funds_to_trade >= (best_ord.size * cur_price) # Case 1: Limit order gets wiped out
                    # Add best_order to match list & decrement outstanding MO
                    push!(order_match_lst, best_ord)
                    funds_to_trade -= (best_ord.size * cur_price)
                    # Update book stats - n_orders & volume
                    sb.total_volume -= best_ord.size
                    sb.num_orders -= 1
                else
                    # left_to_trade < best_ord.size # Case 2: Market Order gets wiped out
                    # Return the difference: LO.size-(MO.funds/cur_price) back to the order book
                    size_outstanding = funds_to_trade / cur_price
                    return_ord =
                        copy_modify_size(best_ord, best_ord.size - size_outstanding)
                    pushfirst!(price_queue, return_ord)
                    # Add remainder to match list & decrement outstanding MO
                    best_ord = copy_modify_size(best_ord, size_outstanding)
                    push!(order_match_lst, best_ord)
                    funds_to_trade -= funds_to_trade
                    # Update book stats - only volume, since we placed an order back
                    sb.total_volume -= size_outstanding
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
    return order_match_lst, funds_to_trade
end




"""
    submit_market_order!(ob::OrderBook,side::Symbol,mo_size) 

Submit market order to `ob::OrderBook` on given side (`:ASK` or `:BID`) and size `mo_size`.

Market orders are filled by price-time priority.

Returns tuple `( ord_lst::Vector{Order}, left_to_trade::ST )`
where
 - `ord_lst` is a list of _limit orders_ that _market order_ matched with
 - `left_to_trade` is the remaining size of un-filled order ( `==0` if order is complete, `>0` if incomplete)

"""
function submit_market_order!(
    ob::OrderBook{Oid,Aid,ST,PT},
    side::Symbol,
    mo_size::Real,
) where {Oid,Aid,ST,PT}
    side ∈ (:BID, :ASK) || error("invalid trade side provided") # check valid side
    if side == :ASK
        return _submit_market_order_bysize!(ob.ask_orders, ST(mo_size))
    else
        return _submit_market_order_bysize!(ob.bid_orders, ST(mo_size))
    end
end


"""
    submit_market_order_byfunds!(ob::OrderBook,side::Symbol,funds) 

Submit market order to `ob::OrderBook` on given side (`:ASK` or `:BID`) with available funds `funds::Real`.

Market orders are filled by price-time priority.

Functionality is exactly the same as `submit_market_order!` except _available funds_ (max total price paid on order) 
is provided, rather than _number of shares_ (order size).

Returns tuple `( ord_lst::Vector{Order}, funds_leftover )`
where
 - `ord_lst` is a list of _limit orders_ that _market order_ matched with
 - `funds_leftover` is the amount of remaining funds if not enough liquidity was available ( `==0` if order is complete, `>0` if incomplete)

"""
function submit_market_order_byfunds!(ob::OrderBook, side::Symbol, funds::Real)
    side ∈ (:BID, :ASK) || error("invalid trade side provided") # check valid side
    if side == :ASK
        return _submit_market_order_byfunds!(ob.ask_orders, funds)
    else
        return _submit_market_order_byfunds!(ob.bid_orders, funds)
    end
end


"""
    clear_book!(ob::OrderBook,n_keep::Int64=10)

Remove all orders beyond `n_keep ≥ 0` from the best bid and best ask.
When `n_keep==0`, all orders are cleared.

"""
function clear_book!(ob::OrderBook{Oid,Aid,ST,PT},n_keep::Int64=10) where {Oid,Aid,ST,PT}
    (n_keep<0) && error("$n_keep should be non-negative")
    # clear the bids
    cleared_bids = Vector{Order{Oid,Aid,ST,PT}}()
    bids_to_clear = [ abs(k) for (k,v) in ob.bid_orders.book ]
    bids_to_clear = bids_to_clear |> x -> last(x, max(length(x) - n_keep,0)) # clear all but last n
    for px in bids_to_clear
        cleared_queue = _delete_price_queue!(ob.bid_orders,px)
        append!(cleared_bids,cleared_queue.queue)
    end
    # clear the asks
    cleared_asks = Vector{Order{Oid,Aid,ST,PT}}()
    asks_to_clear = [ abs(k) for (k,v) in ob.ask_orders.book ]
    asks_to_clear = asks_to_clear |> x -> first(x, max(length(x) - n_keep,0)) # clear all but last n
    for px in asks_to_clear
        cleared_queue = _delete_price_queue!(ob.ask_orders,px)
        append!(cleared_asks,cleared_queue.queue)
    end    
    return cleared_bids, cleared_asks
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
order_types(::Order{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid, Aid, ST, PT
order_types(::OrderQueue{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid, Aid, ST, PT
order_types(::OneSidedBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid, Aid, ST, PT
order_types(::OrderBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT} = Oid, Aid, ST, PT



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
get_acct(ob::OrderBook{Oid,Aid,ST,PT}, acct_id::Aid) where {Oid,Aid,ST,PT} =
    get(ob.acct_map, acct_id, nothing)


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


@inline function _print_book_barplot(
    io::IO,
    ob::OrderBook{Oid,Aid,ST,PT}
) where {Oid,Aid,ST,PT}
    # Get book info
    max_depth = ob.flags[:PlotTickMax]
    sb_info = LimitOrderBook.book_depth_info(ob, max_depth = max_depth)
    all_prices = [sb_info[:BID][:price]; sb_info[:ASK][:price]]

    println(io, "\n Order Book shape (within $max_depth ticks of center)")

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
        print(io, "\n    :BID   <empty>\n")
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
        print(io, "\n    :ASK   <empty>\n")
    end

    return
end

function _print_book_info(io::IO, ob::OrderBook{Oid,Aid,ST,PT}) where {Oid,Aid,ST,PT}
    return print(
        io,
        "OrderBook{Oid=$Oid,Aid=$Aid,ST=$ST,PT=$PT} with properties:\n",
        "  ⋄ best bid/ask price: $(best_bid_ask(ob))\n",
        "  ⋄ total bid/ask volume: $(volume_bid_ask(ob))\n",
        "  ⋄ total bid/ask orders: $(n_orders_bid_ask(ob))\n",
        "  ⋄ flags = $(ob.flags)",
    )
end

Base.print(io::IO, ob::OrderBook) = _print_book_info(io, ob)

function Base.show(io::IO, ::MIME"text/plain", ob::OrderBook)
    println(io, ob)
    _print_book_barplot(io, ob)
    return
end

