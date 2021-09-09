
"""
    submit_limit_order!(
        ob::OrderBook{Sz,Px,Oid,Aid},
        orderid::Oid,
        side::OrderSide,
        limit_price::Real,
        limit_size::Real,
        [, acct_id::Aid, fill_mode::OrderTraits ]
    )

Enter limit order with size `limit_size`, price `limit_price` with `side::OrderSide` into `ob::OrderBook`.

If an account if `acct_id` is provided, account holdings are tracked in `ob.acct_map`.

Order execution logic can be modified according to the argument `fill_mode::`[`OrderTraits`](@ref) which
defaults to `fill_mode=VANILLA_FILLTYPE`, representing the default order matching mode. 

`submit_limit_order!` returns tuple of 
 - `new_open_order::Order` representing the order left in the book after matching. Is `nothing` if no order was inserted
 - `order_match_lst::Vector{Order}` representing the matched orders if the order crosses the book.
 - `left_to_trade::Sz` representing the size of the portion of the order which could neither inserted nor matched.

"""
function submit_limit_order!(
    ob::OrderBook{Sz,Px,Oid,Aid},
    orderid::Oid,
    side::OrderSide,
    limit_price::Real,
    limit_size::Real,
    acct_id::Union{Nothing,Aid}=nothing,
    fill_mode::OrderTraits=VANILLA_FILLTYPE,
) where {Sz,Px,Oid,Aid}
    # Part 0 - Check Arguments
    if !((limit_price > zero(limit_price)) && (limit_size > zero(limit_size)))
        error("Both limit_price and limit_size must be positive")
    end
    ## Part 1 - Cross the Order if appropriate
    best_bid, best_ask = best_bid_ask(ob) # check that price in right range
    if allows_cross(fill_mode) &&
       isbuy(side) &&
       !isnothing(best_ask) &&
       (limit_price >= best_ask) # order is bid (buy) and can cross
        cross_match_lst, remaining_size = _walk_order_book_bysize!(
            ob.ask_orders, Sz(limit_size), Px(limit_price), fill_mode
        )
    elseif allows_cross(fill_mode) &&
           !isbuy(side) &&
           !isnothing(best_ask) &&
           (limit_price >= best_ask) # order is ask (sell) and can cross
        cross_match_lst, remaining_size = _walk_order_book_bysize!(
            ob.bid_orders, Sz(limit_size), Px(limit_price), fill_mode
        )
    else # order can or does not cross, return empty matches
        cross_match_lst, remaining_size = Vector{Order{Sz,Px,Oid,Aid}}(), Sz(limit_size)
    end

    ## Part 2 - Rest the remaining order in the book if possible
    if allows_book_insert(fill_mode) && !iszero(remaining_size) # if there are remaining shares, try to add remaining to the LOB
        best_bid, best_ask = best_bid_ask(ob) # new best bid and ask
        if isbuy(side) && (isnothing(best_ask) || (limit_price < best_ask)) # if order is a buy and limit price is valid for resting order
            # create and insert order object into BID book
            new_open_order = Order{Sz,Px,Oid,Aid}(
                side, remaining_size, limit_price, orderid, acct_id
            )
            insert_order!(ob.bid_orders, new_open_order)
            # if account_id present, add order account map
            isnothing(acct_id) || _add_order_acct_map!(ob.acct_map, acct_id, new_open_order)
            # set remaining size to zero
            remaining_size = zero(Sz)
        elseif !isbuy(side) && (isnothing(best_bid) || (limit_price > best_bid)) # if order is a sell and limit price is valid for resting order
            # create and insert order object into ASK book
            new_open_order = Order{Sz,Px,Oid,Aid}(
                side, remaining_size, limit_price, orderid, acct_id
            )
            insert_order!(ob.ask_orders, new_open_order)
            # if account_id present, add order account map
            !isnothing(acct_id) &&
                _add_order_acct_map!(ob.acct_map, acct_id, new_open_order)
            # set remaining size to zero
            remaining_size = zero(Sz)
        else # if not appropriate to insert new order, register new order as nothing
            new_open_order = nothing
        end
    else
        new_open_order = nothing
    end

    ## Part 3 - Return information
    return (
        new_open_order, cross_match_lst, remaining_size
    )::Tuple{Union{Order{Sz,Px,Oid,Aid},Nothing},Vector{Order{Sz,Px,Oid,Aid}},Sz}
end

@inline _is_best_price_inside_limit(::OneSidedBook, ::Nothing) = true

@inline function _is_best_price_inside_limit(
    sb::OneSidedBook{Sz,Px,Oid,Aid}, limit_price::Px
) where {Sz,Px,Oid,Aid}
    if isbidbook(sb)
        return sb.best_price >= limit_price
    else
        return sb.best_price <= limit_price
    end
end

"""
    _walk_order_book_bysize!(
        sb::OneSidedBook{Sz,Px,Oid,Aid},
        order_size::Sz,
        limit_price::Union{Px,Nothing},
        order_mode::OrderTraits,
    )

Cross (limit or market) order with opposite single side of book. 
Order size is specified in number of shares.
Return matches and outstanding size.

__Notes__
 - If `limit_price::Nothing`, order is treated as Market Order
 - Function expects `order_size>0` and `limit_price>0`

"""
function _walk_order_book_bysize!(
    sb::OneSidedBook{Sz,Px,Oid,Aid},
    order_size::Sz,
    limit_price::Union{Px,Nothing},
    order_mode::OrderTraits,
)::Tuple{Vector{Order{Sz,Px,Oid,Aid}},Sz} where {Sz,Px,Oid,Aid}
    # Allocate memory for order output
    order_match_lst = Vector{Order{Sz,Px,Oid,Aid}}()
    shares_left = order_size # remaining quantity to trade
    # Perform initial available liquidity check
    if isallornone(order_mode) && (_size_available(sb, limit_price) < order_size)
        return order_match_lst, shares_left
    end
    # Perform matching logic
    limit_price_check = Base.Fix2(_is_best_price_inside_limit, limit_price)
    while !isempty(sb.book) && !iszero(shares_left) && limit_price_check(sb) # while book not empty, order not done and best price within limit price
        price_queue::OrderQueue = _popfirst_queue!(sb)
        if price_queue.total_volume[] <= shares_left # If entire queue is to be wiped out
            append!(order_match_lst, price_queue.queue) # Add all of the orders to the match list
            shares_left -= price_queue.total_volume[] # decrement what's left to trade
        else
            while !isempty(price_queue) && !iszero(shares_left) # while not done and queue not empty 
                best_ord::Order = popfirst!(price_queue) # pop out best order
                if shares_left >= best_ord.size # Case 1: Limit order gets wiped out
                    # Add best_order to match list & decrement outstanding MO
                    push!(order_match_lst, best_ord)
                    shares_left -= best_ord.size
                else
                    # shares_left < best_ord.size # Case 2: Market Order gets wiped out
                    # Return the difference: LO.size-MO.size back to the order book
                    return_ord = copy_modify_size(best_ord, best_ord.size - shares_left)
                    pushfirst!(price_queue, return_ord)
                    # Add remainder to match list & decrement outstanding MO
                    best_ord = copy_modify_size(best_ord, shares_left)
                    push!(order_match_lst, best_ord)
                    shares_left -= best_ord.size
                end
            end
            if !isempty(price_queue) # If price queue wasn't killed, put it back into the OneSidedBook
                _insert_queue!(sb, price_queue)
            end
        end
    end
    # Return results
    return order_match_lst, shares_left
end

"""
Fill market order by walking the book using Price/Arrival priority. 
__This version walks the book with funds rather than trade size.__
"""
function _walk_order_book_byfunds!(
    sb::OneSidedBook{Sz,Px,Oid,Aid},
    order_funds::Real,
    limit_price::Union{Px,Nothing},
    order_mode::OrderTraits,
)::Tuple{Vector{Order{Sz,Px,Oid,Aid}},Real} where {Sz,Px,Oid,Aid}
    # Allocate memory for order output
    order_match_lst = Vector{Order{Sz,Px,Oid,Aid}}()
    funds_left = order_funds # remaining quantity to trade
    # Perform initial available liquidity check
    if isallornone(order_mode) && (_size_available(sb, limit_price) < order_size)
        return order_match_lst, funds_left
    end
    # Perform matching logic
    limit_price_check = Base.Fix2(_is_best_price_inside_limit, limit_price)
    while !isempty(sb.book) && !iszero(funds_left) && limit_price_check(sb) # while book not empty, order not done and best price within limit price
        price_queue::OrderQueue = popfirst_queue!(sb)
        if (price_queue.total_volume[] * price_queue.price) <= funds_left # If entire queue is to be wiped out
            append!(order_match_lst, price_queue.queue) # Add all of the orders to the match list
            funds_left -= price_queue.total_volume[] * price_queue.price # decrement what's left to trade
        else
            while !isempty(price_queue) && !iszero(funds_left) # while not done and queue not empty 
                best_ord::Order = popfirst!(price_queue) # pop out best order
                if funds_left >= (best_ord.size * best_ord.price) # Case 1: Limit order gets wiped out
                    # Add best_order to match list & decrement outstanding MO
                    push!(order_match_lst, best_ord)
                    funds_left -= (best_ord.size * best_ord.price)
                else # funds_left < best_ord.size # Case 2: Market Order gets wiped out
                    # Return the difference: LO.size-MO.size back to the order book
                    rem_match_size = floor(Sz, funds_left / best_ord.price)
                    return_ord = copy_modify_size(best_ord, best_ord.size - rem_match_size)
                    pushfirst!(price_queue, return_ord)
                    # Add remainder to match list & decrement outstanding MO
                    best_ord = copy_modify_size(best_ord, rem_match_size)
                    push!(order_match_lst, best_ord)
                    funds_left -= (best_ord.size * best_ord.price)
                end
            end
            if !isempty(price_queue) # If price queue wasn't killed, put it back into the OneSidedBook
                _insert_queue!(sb, price_queue)
            end
        end
    end
    # Return results
    return order_match_lst, funds_left
end

"""
    submit_market_order!(ob::OrderBook,side::OrderSide,mo_size[,fill_mode::OrderTraits]) 

Submit market order to `ob::OrderBook` with `side::OrderSide` and size `mo_size`.
Optionally `mode::OrderTraits` may be provided to modify fill logic.
Market orders are filled by price-time priority.

Returns tuple `( ord_lst::Vector{Order}, left_to_trade::Sz )`
where
 - `ord_lst` is a list of _limit orders_ that _market order_ matched with
 - `left_to_trade` is the remaining size of un-filled order ( `==0` if order is complete, `>0` if incomplete)

__Note:__ Only `mode.allornone` will be considered from `mode::OrderTraits`.
All other entries will be ignored.

"""
function submit_market_order!(
    ob::OrderBook{Sz,Px,Oid,Aid},
    side::OrderSide,
    mo_size::Real;
    fill_mode::OrderTraits=VANILLA_FILLTYPE,
) where {Sz,Px,Oid,Aid}
    mo_size > zero(mo_size) || error("market order argument mo_size must be positive")
    if isbuy(side)
        return _walk_order_book_bysize!(ob.ask_orders, Sz(mo_size), nothing, fill_mode)
    else
        return _walk_order_book_bysize!(ob.bid_orders, Sz(mo_size), nothing, fill_mode)
    end
end

"""
    submit_market_order_byfunds!(ob::OrderBook,side::Symbol,funds[,mode::OrderTraits]) 

Submit market order to `ob::OrderBook` `side::OrderSide` and available funds `funds::Real`.
Optionally `mode::OrderTraits` may be provided to modify fill logic.
Market orders are filled by price-time priority.

Functionality is exactly the same as `submit_market_order!` except _available funds_ (max total price paid on order) 
is provided, rather than _number of shares_ (order size).

Returns tuple `( ord_lst::Vector{Order}, funds_leftover )`
where
 - `ord_lst` is a list of _limit orders_ that _market order_ matched with
 - `funds_leftover` is the amount of remaining funds if not enough liquidity was available ( `==0` if order is complete, `>0` if incomplete)

__Note:__ Only `mode.allornone` will be considered from `mode::OrderTraits`.
All other entries will be ignored.

"""
function submit_market_order_byfunds!(
    ob::OrderBook, side::OrderSide, funds::Real, fill_mode::OrderTraits=VANILLA_FILLTYPE
)
    funds > zero(funds) || error("market order argument funds must be positive")
    if isbuy(side)
        return _walk_order_book_byfunds!(ob.ask_orders, funds, nothing, fill_mode)
    else
        return _walk_order_book_byfunds!(ob.bid_orders, funds, nothing, fill_mode)
    end
end

# Order Cancellation functions

"""
    cancel_order!(ob::OrderBook, o::Order)
    cancel_order!(ob::OrderBook, orderid, side, price [, acct_id=nothing])

Cancels Order `o`, or order with matching information from OrderBook.

Provide `acct_id` if known to guarantee correct account tracking.
"""
function cancel_order!(
    ob::OrderBook{Sz,Px,Oid,Aid}, orderid::Oid, side::OrderSide, price
) where {Sz,Px,Oid,Aid}
    # Delete order from bid (buy) or ask (sell) book
    if isbuy(side)
        popped_ord = pop_order!(ob.bid_orders, Px(price), orderid)
    else
        popped_ord = pop_order!(ob.ask_orders, Px(price), orderid)
    end
    # Delete order from account maps
    if !isnothing(popped_ord) && !isnothing(popped_ord.acctid)
        _delete_order_acct_map!(ob.acct_map, popped_ord.acctid, popped_ord.orderid)
    end
    return popped_ord
end

cancel_order!(ob::OrderBook, o::Order) = cancel_order!(ob, o.orderid, o.side, o.price)
