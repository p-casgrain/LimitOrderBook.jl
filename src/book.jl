using UnicodePlots: barplot
using Base: show, print


"""
    AcctMap{Oid,Aid}

Collection of open orders by account. 
Aid, Oid represent the type of the account and order ids, respectively.
The account map has a nested Dict structure. 
Outer key is account id, mapping to AVLTree of Orders keyed by order id.
"""
AcctMap{Oid<:Integer,Aid<:Integer} = Dict{Aid,AVLTree{Oid,Order{Oid,Aid}}}


"""
Limit Order Book Object - `OrderBook{Oid<:Integer,Aid<:Integer}`

Oid and Aid represent the Order and Account ID types

Fields: 
    `bid_orders::OneSideBook{Oid,Aid}` - book of bid orders
    `ask_orders::OneSideBook{Oid,Aid}` - book of ask orders
    `acct_map::AcctMap{Oid,Aid}` mapping account ids to orders

Initialize empty book: `OrderBook{Oid,Aid}()`
"""
@kwdef mutable struct OrderBook{Oid<:Integer,Aid<:Integer}
    bid_orders::OneSidedBook{Oid,Aid} = OneSidedBook{Oid,Aid}(side = :BID) # bid orders
    ask_orders::OneSidedBook{Oid,Aid} = OneSidedBook{Oid,Aid}(side = :ASK) # ask orders
    acct_map::AcctMap{Oid,Aid} = AcctMap{Oid,Aid}() # Map from acct_id::Aid to AVLTree{order_id::Oid,Order{Oid,Aid}}
    flags = Dict{Symbol,Bool}(:LOAutoCross => true) # container for additional order book logic flags
end

OrderBook() = OrderBook{Int64,Int64}

## Limit Order Submission and Cancellation functions

@inline function _add_order_acct_map!(
    acct_map::AcctMap{Oid,Aid},
    acct::Union{Aid,Nothing},
    order::Order{Oid,Aid},
) where {Oid,Aid}
    if !isnothing(acct)
        if !haskey(acct_map, acct)
            acct_map[acct] = AVLTree{Oid,Order{Oid,Aid}}() # If account isn't registered, register
        end
        insert!(acct_map[acct], order.orderid, order) # Add order to account map
    end
end

@inline function _delete_order_acct_map!(
    acct_map,
    acct::Union{Aid,Nothing},
    orderid::Oid,
) where {Oid,Aid}
    if !isnothing(acct)
        !haskey(acct_map, acct) ? nothing : delete!(acct_map[acct], orderid)
    end
end


"""
    `submit_limit_order!(ob::OrderBook, orderid::Int64, price::Float32, size::Int64, side::Symbol, acct_id::Union{Nothing,Int64}=nothing)`

Enter limit order with matching properties to the LOB. 
Optionally provide `acct_id`, defaults to `nothing`. If `acct_id` provided, account holdings are tracked in 
"""
function submit_limit_order!(
    ob::OrderBook{Oid,Aid},
    orderid::Oid,
    price::Float32,
    size::Int64,
    side::Symbol;
    acct_id::Union{Nothing,Aid} = nothing,
) where {Oid,Aid}
    side in (:BID, :ASK) || error("invalid trade side provided") # check valid side
    ord = Order{Oid,Aid}(orderid, side, size, price, acct_id) # create order object
    # Add actual order to the correct OneSideBook
    ord.side == :ASK ? insert_order!(ob.ask_orders, ord) : insert_order!(ob.bid_orders, ord)
    # Update account map
    _add_order_acct_map!(ob.acct_map, acct_id, ord)
    return nothing
end


"""
    `cancel_limit_order!(ob::OrderBook, 
                            orderid::Int64, 
                            price::Float32, 
                            side::Symbol, 
                            acct_id::Union{Nothing,Int64}=nothing)`

Cancels order with matching tick_id from OrderBook.
Optionally provide acct_id if known.

"""
function cancel_limit_order!(
    ob::OrderBook{Oid,Aid},
    orderid::Oid,
    price::Float32,
    side::Symbol;
    acct_id::Union{Nothing,Aid} = nothing,
) where {Oid,Aid}
    side in (:BID, :ASK) || error("invalid trade side provided") # check valid side
    # Delete order from bid or ask book
    (side == :ASK) ? delete_order!(ob.ask_orders, price, orderid) :
    delete_order!(ob.bid_orders, price, orderid)
    # Delete order from account maps
    isnothing(acct_id) || _delete_order_acct_map!(ob.acct_map, acct_id, orderid)
end



## Market Order insertion functions

"""
    Fill market order by walking the book using Price/Arrival priority
"""
@inline function _submit_market_order!(sb::OneSidedBook, size::Int64)
    size > 0 || error("market order size must be positive")
    order_match_lst = Vector{Order}()
    left_to_trade = size # remaining quantity to trade
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
    complete_status = left_to_trade > 0 ? :INCOMPLETE : :COMPLETE # Note whether order is complete
    return order_match_lst, complete_status
end




"""
    `submit_market_order!(ob,side,size)` 

Submit market to OrderBook on given side (:ASK or :BID) and size::Int64,
Returns the assigned internal tick_id.

"""
function submit_market_order!(ob::OrderBook, side, size)
    side ∈ (:BID, :ASK) || error("invalid trade side provided") # check valid side
    if side == :ASK
        order_match_lst, complete_status = _submit_market_order!(ob.ask_orders, size::Int64)
    else
        order_match_lst, complete_status = _submit_market_order!(ob.bid_orders, size::Int64)
    end
    return order_match_lst, complete_status
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
        :side => sb.side,
        :price => [x[1] for x in raw_info_list],
        :volume => [x[2] for x in raw_info_list],
        :orders => [x[3] for x in raw_info_list],
    )
end

"""
    `book_depth_info(ob::OrderBook; max_depth=5)`

    Retrieve prices, volumes and order counts at bid and ask until fixed depth
"""
function book_depth_info(ob::OrderBook; max_depth = 5)
    return Dict(
        :BID => _sidebook_stats(ob.bid_orders, max_depth),
        :ASK => _sidebook_stats(ob.ask_orders, max_depth),
    )
end

"Return best ask price from order book"
best_bid_ask(ob::OrderBook) = (ob.bid_orders.best_price, ob.ask_orders.best_price)

"""
    `volume_bid_ask(ob::OrderBook)`

Return total bid and ask volume from order book.
"""
volume_bid_ask(ob::OrderBook) = (ob.bid_orders.total_volume, ob.ask_orders.total_volume)

"""
    n_orders_bid_ask(ob::OrderBook)

Return total number of orders on each side of order book
"""
n_orders_bid_ask(ob::OrderBook) = (ob.bid_orders.num_orders, ob.ask_orders.num_orders)


"""
    get_acct(ob::OrderBook{Oid,Aid},acct_id::Aid)

Return all open orders assigned to 
"""
get_acct(ob::OrderBook{Oid,Aid}, acct_id::Aid) where {Oid,Aid} = ob.acct_map[acct_id]


"""
    `write_csv(io::IO,ob::OrderBook;row_formatter = _order_to_csv, header="TRD,ID,SIDE,SIZE,PX,ACCT")`

Write OrderBook `ob` to an IO stream into csv format where each row corresponds to an order
The formatting for each row is given by the function `string_map(::Order)::String`.
The csv header can be provided as an argument where setting it to `nothing` writes no header.
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


@inline function _print_book_barplot(io::IO, ob::OrderBook{Oid,Aid}; max_depth = 5) where {Oid,Aid}
    # Get book info
    sb_info = LimitOrderBook.book_depth_info(ob, max_depth = max_depth)
    all_prices = [sb_info[:BID][:price]; sb_info[:ASK][:price]]
    
    println(io,"  display cutoff: $max_depth ticks")

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

function _print_book_info(io::IO,ob::OrderBook{Oid,Aid}) where {Oid,Aid}
    return print(io, 
            "OrderBook{$Oid,$Aid}\n",
            "  best bid/ask price: $(best_bid_ask(ob))\n",
            "  total bid/ask volume: $(volume_bid_ask(ob))\n",
            "  total bid/ask orders: $(n_orders_bid_ask(ob))\n",
            "  flags = $(ob.flags)")
end

Base.print(io::IO, ob::OrderBook) = _print_book_info(io,ob)

function Base.show(io::IO, ::MIME"text/plain", ob::OrderBook; max_depth = 5)
    println(io,ob)
    _print_book_barplot(io, ob; max_depth = max_depth)
    return 
end

