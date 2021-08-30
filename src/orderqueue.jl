using Printf

# Define Order, OrderQueue objects and relavant methods.
"""
    Order{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}

Type representing a limit order.

An `Order{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}` is a struct representing a Limit Order which contains

 - An unique order id `orderid::Oid`, 
 - `side::Symbol`, the side of the book the order will rest in, where either `side=:ASK` or `side=:BID`.
 - `size::ST`, the order size
 - `price::PT`, the price the order is set at
 - Optionally, a unique account ID `acctid::Union{Aid,Nothing}`, which is set to nothing if the account is unknown or irrelevant.

One can create a new `Order` as `Order{Oid,Aid,ST,PT}(orderid, side, size, price [,acctid=nothing])`, where the types of 
`size` and `price` will be cast to the correct types. The `orderid` and `acctid` types will not be cast in order to avoid ambiguity.

"""
struct Order{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
    orderid::Oid
    side::Symbol
    size::ST
    price::PT
    acctid::Union{Aid,Nothing}
    function Order{Oid,Aid,ST,PT}(
        orderid::Oid,
        side::Symbol,
        size::Real,
        price::Real,
        acctid::Union{Aid,Nothing} = nothing,
    ) where {Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
        new{Oid,Aid,ST,PT}(orderid, side, ST(size), PT(price), acctid) # cast price and size to correct types
    end
end

# Orderbook State Saving Methods
function _order_to_csv(o::Order)
    @sprintf "LMT,%i,%s,%f,%f,%i" o.orderid o.side o.size o.price o.acctid
end


"Return new order with size modified"
copy_modify_size(o::Order{Oid,Aid,ST,PT}, new_size) where {Oid,Aid,ST,PT} =
    Order{Oid,Aid,ST,PT}(o.orderid, o.side, new_size, o.price, o.acctid)


""""
OrderQueue is a queue of orders at a fixed price, implemented as a Deque/Vector.

OrderQueue.queue is a Vector (interpreted as double ended queue). Orders are added and removed via FIFO logic.
OrderQueue also keeps track of its contained volume in shares and orders

OrderQueue(price) Initializes an empty order queue at price
"""
struct OrderQueue{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
    price::PT # price at which queue is located
    queue::Vector{Order{Oid,Aid,ST,PT}} # queue of orders as vector
    total_volume::Base.RefValue{ST} # total volume in queue
    num_orders::Base.RefValue{Int64} # total size of queue
    # Initialize empty OrderQueue
    function OrderQueue{Oid,Aid,ST,PT}(
        price::PT,
    ) where {Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
        new{Oid,Aid,ST,PT}(
            price,
            Vector{Order{Oid,Aid,ST,PT}}(),
            Base.RefValue{ST}(0),
            Base.RefValue{Int64}(0),
        )
    end
end



# Insert, delete, push, pop orders into/out of OrderQueue
function Base.push!(oq::OrderQueue, ord::Order)
    push!(oq.queue, ord)
    oq.total_volume[] += ord.size
    oq.num_orders[] += 1
end

function Base.pushfirst!(oq::OrderQueue, ord::Order)
    pushfirst!(oq.queue, ord)
    oq.total_volume[] += ord.size
    oq.num_orders[] += 1
end

isequal_orderid(
    o::Order{Oid,Aid,ST,PT},
    this_id::Oid,
) where {Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real} = o.orderid == this_id
order_id_match(order_id) = Base.Fix2(isequal_orderid, order_id)

@inline function _popat_orderid!(
    oq::OrderQueue{Oid,Aid,ST,PT},
    pop_id::Oid,
) where {Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
    ret_ix = findfirst(order_id_match(pop_id), oq.queue)::Union{Int64,Nothing}
    if !isnothing(ret_ix)
        return popat!(oq.queue, ret_ix)::Order{Oid,Aid,ST,PT}
    else
        return nothing
    end
end

"""
    popat_orderid!(oq::OrderQueue, orderid::Integer)

Pop Order with orderid from oq::OrderQueue.

Returns eiter
    popped order, updates queue statistics.
    `nothing` if orderid not found.

"""
function popat_orderid!(oq::OrderQueue, orderid)
    ord = _popat_orderid!(oq, orderid)
    if !isnothing(ord) # if order is returned, track stats
        oq.total_volume[] -= ord.size
        oq.num_orders[] -= 1
    end
    return ord
end

function Base.popfirst!(oq::OrderQueue)
    ord = Base.popfirst!(oq.queue)
    oq.total_volume[] -= ord.size
    oq.num_orders[] -= 1
    return ord
end

Base.isempty(oq::OrderQueue) = isempty(oq.queue)

function Base.print(io::IO, oq::OrderQueue)
    write(io::IO, "OrderQueue at price=$(oq.price):", "\n")
    # write(io," ","TRD,ID,SIDE,SIZE,PX,ACCT",'\n')
    for ord in oq.queue
        write(io::IO, " ")
        print(io::IO, ord)
        write(io::IO, "\n")
        # write(io::IO," ",_order_to_csv(ord),"\n")
    end
end
