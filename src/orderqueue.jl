

# Define Order Fill mode and utilities
"""
    OrderTraits(allornone::Bool,immediateorcancel::Bool,allow_cross::Bool)

`OrderTraits` specify order traits which modify execution logic.

An instance can be initialized by using the keyword intializer or by using the exported constants
`VANILLA_FILLTYPE`, `IMMEDIATEORCANCEL_FILLTYPE`, `FILLORKILL_FILLTYPE`.

The default execution logic is represented by `VANILLA_FILLTYPE`.

__Note:__ This feature is not well supported yet. 
Other than the constants described above, use non-vanilla modes with caution.

"""
Base.@kwdef struct OrderTraits
    allornone::Bool = false
    immediateorcancel::Bool = false
    allow_cross::Bool = true
end

isallornone(mode::OrderTraits) = mode.allornone
isimmediateorcancel(mode::OrderTraits) = mode.immediateorcancel
isfillorkill(mode::OrderTraits) = isallornone(mode)&&isimmediateorcancel(mode)
allows_book_insert(mode::OrderTraits) = !isimmediateorcancel(mode)
allows_partial_fill(mode::OrderTraits) = !isallornone(mode)
allows_cross(mode::OrderTraits) = mode.allow_cross

const VANILLA_FILLTYPE = OrderTraits(false,false,true)
const FILLORKILL_FILLTYPE = OrderTraits(true,true,true)
const IMMEDIATEORCANCEL_FILLTYPE = OrderTraits(false,true,true)
# const ALLORNONE_ORDER = OrderTraits(true,false,true)


Base.string(x::OrderTraits) =
    @sprintf("OrderTraits(allornone=%s,immediateorcancel=%s,allow_cross=%s)",x.allornone,x.immediateorcancel,x.allow_cross)
Base.print(io::IO, x::OrderTraits) = print(io, string(x))
Base.show(io::IO, ::MIME"text/plain", x::OrderTraits) = print(io, string(x))


# Define Order Side and utilities
"""
    OrderSide

Type representing whether an order is a buy order or sell order.
New instance can be generated with `OrderSide(::Bool)` or by using exported constants
`BUY_ORDER` and `SELL_ORDER`
"""
struct OrderSide
    is_buy::Bool
end

Base.string(x::OrderSide) = x.is_buy ? "OrderSide(Buy)" : "OrderSide(Sell)"
Base.print(io::IO, x::OrderSide) = print(io, string(x))
Base.show(io::IO, ::MIME"text/plain", x::OrderSide) = print(io, string(x))
Base.show(io::IO, x::OrderSide) = print(io, string(x))

isbuy(x::OrderSide) = x.is_buy
issell(x::OrderSide) = !x.is_buy

const BUY_ORDER = OrderSide(true)
const SELL_ORDER = OrderSide(false)

# Define Order, OrderQueue objects and relavant methods.
"""
    Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}

Type representing a limit order.

An `Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}` is a struct representing a resting Limit Order which contains

    - `side::OrderSide`, the side of the book the order will rest in. See [`OrderSide`](@ref) for more info.
    - `size::Sz`, the order size
    - `price::Px`, the price the order is set at
    - `orderid::Oid`, a unique Order ID
    - (optional) `acctid::Union{Aid,Nothing}`, which is set to nothing if the account is unknown or irrelevant.

One can create a new `Order` as `Order{Sz,Px,Pid,Aid}(side, size, price, orderid, order_mode [,acctid=nothing])`, where the types of 
`size` and `price` will be cast to the correct types. The `orderid` and `acctid` types will not be cast in order to avoid ambiguity.
"""
struct Order{Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}
    side::OrderSide
    size::Sz
    price::Px
    orderid::Oid
    acctid::Union{Aid,Nothing}
    function Order{Sz,Px,Oid,Aid}(
        side::OrderSide,
        size::Real,
        price::Real,
        orderid::Oid,
        acctid::Union{Aid,Nothing} = nothing,
    ) where {Sz<:Real,Px<:Real,Oid<:Integer,Aid<:Integer}
        new{Sz,Px,Oid,Aid}(side, Sz(size), Px(price), orderid, acctid) # cast price and size to correct types
    end
end

# Order utility functions
has_acct(o::Order) = isnothing(o.acctid)
isbuy(o::Order) = o.side.is_buy


function Base.show(io::IO,o::Order{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    str_lst = [
        "Order{$Sz,$Px,$Oid,$Aid}(",
        "side=$(o.side),",
        "size=$(o.size),",
        "price=$(o.price),",
        "orderid=$(o.orderid),",
        "acctid=$(o.acctid)",
        ")"]
    join(io,str_lst," ")
end

function Base.print(io::IO,o::Order{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    str_lst = [
        "Order{$Sz,$Px,$Oid,$Aid}(",
        "side=$(o.side),",
        "size=$(o.size),",
        "price=$(o.price),",
        "orderid=$(o.orderid),",
        "acctid=$(o.acctid)",
        ")"]
    join(io,str_lst)
end


# Orderbook State Saving Methods
function _order_to_csv(o::Order)
    @sprintf "LMT,%i,%s,%f,%f,%i" o.orderid o.side o.size o.price o.acctid
end


"Return new order with size modified"
copy_modify_size(o::Order{Sz,Px,Oid,Aid}, new_size::Sz) where {Sz,Px,Oid,Aid} =
    Order{Sz,Px,Oid,Aid}(o.side, new_size::Sz, o.price, o.orderid, o.acctid)


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

Base.length(q::OrderQueue,) = length(q.queue)
Base.iterate(q::OrderQueue,i=1) = iterate(q.queue,i)


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
    o.orderid == this_id
order_id_match(order_id) = Base.Fix2(isequal_orderid, order_id)

@inline function _popat_orderid_internal!(
    oq::OrderQueue{Sz,Px,Oid,Aid},
    pop_id::Oid,
) where {Sz,Px,Oid,Aid}
    ret_ix = findfirst(order_id_match(pop_id), oq.queue)::Union{Int64,Nothing}
    return (
        isnothing(ret_ix) ? ret_ix::Nothing : popat!(oq.queue, ret_ix)::Order{Sz,Px,Oid,Aid}
    )::Union{Order{Sz,Px,Oid,Aid},Nothing}
end


"""
    popat_orderid!(oq::OrderQueue, orderid::Integer)

Pop Order with orderid from oq::OrderQueue.

Returns eiter
    popped order, updates queue statistics.
    `nothing` if orderid not found.

"""
function popat_orderid!(oq::OrderQueue{Sz,Px,Oid,Aid}, orderid::Oid) where {Sz,Px,Oid,Aid}
    ord = _popat_orderid_internal!(oq, orderid)
    if !isnothing(ord) # if order is returned, track stats
        oq.total_volume[] -= ord.size
        oq.num_orders[] -= 1
    end
    return ord::Union{Order{Sz,Px,Oid,Aid},Nothing}
end

function Base.popfirst!(oq::OrderQueue{Sz,Px,Oid,Aid}) where {Sz,Px,Oid,Aid}
    if isempty(oq)
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
