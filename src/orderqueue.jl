using Printf

# Define Order Fill mode and utilities
struct OrderFillMode
    is_limit::Bool
    is_allornone::Bool
    is_immediateorcancel::Bool
    OrderFillMode(is_limit = true, is_allornone = false, is_immediateorcancel = false) =
        new(is_limit, is_allornone, is_immediateorcancel)
end

islimitorder(om::OrderFillMode) = om.is_limit
isallornone(om::OrderFillMode) = om.is_allornone
isioc(om::OrderFillMode) = om.is_immediateorcancel

const VANILLA_MARKET_ORDER = OrderFillMode(false, false, false)
const VANILLA_LIMIT_ORDER = OrderFillMode(true, false, false)
const ALLORNONE_MARKET_ORDER = OrderFillMode(false, true, false)
const ALLORNONE_LIMIT_ORDER = OrderFillMode(true, true, false)
const IOC_MARKET_ORDER = OrderFillMode(false, false, true)
const IOC_LIMIT_ORDER = OrderFillMode(true, false, true)
const FILLORKILL_MARKET_ORDER = OrderFillMode(false, true, true)
const FILLORKILL_LIMIT_ORDER = OrderFillMode(true, true, true)

Base.string(x::OrderFillMode) =
    @printf "OrderFillMode(is_limit=%s,is_allornone=%s,is_immediateorcancel=%s)" x.is_limit x.is_allornone x.is_immediateorcancel
Base.print(io::IO, x::OrderFillMode) = print(io, string(x))
Base.show(io::IO, ::MIME"text/plain", x::OrderFillMode) = println(io, string(x))


# Define Order Side Type and utilities
struct OrderSide
    is_buy::Bool
end

Base.string(x::OrderSide) = x.is_buy ? "BuyOrder" : "SellOrder"
Base.print(io::IO, x::OrderSide) = print(io, string(x))
Base.show(io::IO, ::MIME"text/plain", x::OrderSide) = println(io, string(x))
Base.show(io::IO, x::OrderSide) = println(io, string(x))
const BUY_ORDER = OrderSide(true)
const SELL_ORDER = OrderSide(false)

# Define Order, OrderQueue objects and relavant methods.
"""
    Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}

Type representing a limit order.

An `Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}` is a struct representing a Limit Order which contains

    - `side::OrderSide`, the side of the book the order will rest in, where either `side=:ASK` or `side=:BID`.
    - `size::Sz`, the order size
    - `price::Px`, the price the order is set at
    - `orderid::Oid`, a unique Order ID
    - `order_mode::OrderFillMode` representing how the order is to be filled
    - (optional) `acctid::Union{Aid,Nothing}`, which is set to nothing if the account is unknown or irrelevant.

One can create a new `Order` as `Order{Sz,Px,Pid,Aid}(side, size, price, orderid, order_mode [,acctid=nothing])`, where the types of 
`size` and `price` will be cast to the correct types. The `orderid` and `acctid` types will not be cast in order to avoid ambiguity.

"""
struct Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}
    side::OrderSide
    size::Sz
    price::Px
    orderid::Oid
    order_mode::OrderFillMode
    acctid::Union{Aid,Nothing}
    function Order{Sz,Px}(
        side::Symbol,
        size::Real,
        price::Real,
        orderid::Oid,
        order_mode::OrderFillMode,
        acctid::Union{Aid,Nothing} = nothing,
    ) where {Oid<:Integer,Aid<:Integer,Sz<:Real,Px<:Real}
        new{Oid,Aid,Sz,Px}(side, SzT(size), Px(price), orderid, order_mode, acctid) # cast price and size to correct types
    end
end

has_acct(o::Order) = isnothing(o.acctid)


"""
    order_types(::Order{Sz,Px,Oid,Aid})

Return parametric types of either an `Order`, `OrderQueue`, `OneSidedbook` or `OrderBook`.


"""
order_types(::Order{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid} = Sz, Px, Oid, Aid
order_types(::Type{Order{Sz,Px,Oid,Aid}}) where {Sz,Px,Oid,Aid} = Sz, Px, Oid, Aid

# order_types(::OrderQueue{Oid,Aid,Sz,Px}) where {Oid,Aid,Sz,Px} = Oid, Aid, Sz, Px
# order_types(::OneSidedBook{Oid,Aid,Sz,Px}) where {Oid,Aid,Sz,Px} = Oid, Aid, Sz, Px
# order_types(::OrderBook{Oid,Aid,Sz,Px}) where {Oid,Aid,Sz,Px} = Oid, Aid, Sz, Px



# Orderbook State Saving Methods
function _order_to_csv(o::Order)
    @sprintf "LMT,%i,%s,%f,%f,%i" o.orderid o.side o.size o.price o.acctid
end


"Return new order with size modified"
copy_modify_size(o::Order{Sz,Px,Oid,Aid}, new_size::Sz) where {Sz,Px,Oid,Aid} =
    Order{Sz,Px,Oid,Aid}(o.side, new_size::Sz, o.price, o.orderid, o.order_mode, o.acctid)


""""
OrderQueue is a queue of orders at a fixed price, implemented as a Deque/Vector.

OrderQueue.queue is a Vector (interpreted as double ended queue). Orders are added and removed via FIFO logic.
OrderQueue also keeps track of its contained volume in shares and orders

OrderQueue(price) Initializes an empty order queue at price
"""
struct OrderQueue{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}
    price::Px # price at which queue is located
    queue::Vector{Order{Sz,Px,Oid,Aid}} # queue of orders as vector
    total_volume::Base.RefValue{Sz} # total volume in queue
    num_orders::Base.RefValue{Int64} # total size of queue
    # Initialize empty OrderQueue
    function OrderQueue{Sz,Px,Oid,Aid}(price::Px) where {Sz,Px,Oid,Aid}
        new{Sz,Px,Oid,Aid}(
            price,
            Vector{Order{Sz,Px,Oid,Aid}}(),
            Base.RefValue{Sz}(0),
            Base.RefValue{Int64}(0),
        )
    end
end



# Insert, delete, push, pop orders into/out of OrderQueue
function Base.push!(
    oq::OrderQueue{Sz,Px,Oid,Aid},
    ord::Order{Sz,Px,Oid,Aid},
) where {Sz,Px,Oid,Aid}
    push!(oq.queue, ord)
    oq.total_volume[] += ord.size::Sz
    oq.num_orders[] += 1
end

function Base.pushfirst!(
    oq::OrderQueue{Sz,Px,Oid,Aid},
    ord::Order{Sz,Px,Oid,Aid},
) where {Sz,Px,Oid,Aid}
    pushfirst!(oq.queue, ord)
    oq.total_volume[] += ord.size::Sz
    oq.num_orders[] += 1
end

isequal_orderid(o::Order{<:Real,<:Real,Oid,<:Real}, this_id::Oid) where {Oid<:Integer} =
    o.orderid === this_id
order_id_match(order_id) = Base.Fix2(isequal_orderid, order_id)

@inline function _popat_orderid!(
    oq::OrderQueue{Sz,Px,Oid,Aid},
    pop_id::Oid,
) where {Sz,Px,Oid,Aid,Ord<:Order{Sz,Px,Oid,Aid}}
    ret_ix = findfirst(order_id_match(pop_id), oq.queue)::Union{Int64,Nothing}
    return (
        isnothing(ret_ix) ? ret_ix::Nothing : popat!(oq.queue, ret_ix)::Ord
    )::Union{Ord,Nothing}
end


"""
    popat_orderid!(oq::OrderQueue, orderid::Integer)

Pop Order with orderid from oq::OrderQueue.

Returns eiter
    popped order, updates queue statistics.
    `nothing` if orderid not found.

"""
function popat_orderid!(oq::OrderQueue{Sz,Px,Oid,Aid}, orderid::Oid) where {Sz,Px,Oid,Aid}
    ord = _popat_orderid!(oq, orderid)
    if !isnothing(ord) # if order is returned, track stats
        oq.total_volume[] -= ord.size
        oq.num_orders[] -= 1
    end
    return ord::Union{Order{Sz,Px,Oid,Aid},Nothing}
end

function Base.popfirst!(oq::OrderQueue{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    if isempty(oq.queue)
        return nothing
    else
        ord = Base.popfirst!(oq.queue)
        oq.total_volume[] -= ord.size
        oq.num_orders[] -= 1
        return ord
    end
end

Base.isempty(oq::OrderQueue) = isempty(oq.queue)

function Base.print(io::IO, oq::OrderQueue)
    write(io::IO, "OrderQueue at price=$(oq.price):", "\n")
    for ord in oq.queue
        write(io::IO, " ")
        print(io::IO, ord)
        write(io::IO, "\n")
    end
end
