using Printf

# Define Order, OrderQueue objects and relavant methods.
"""
    Order{Tid} 
    Order object with order ID type Oid and account id type Aid
"""
struct Order{Oid<:Integer,Aid<:Integer}
    orderid::Oid
    side::Symbol
    size::Int64
    price::Float32
    acctid::Union{Aid,Nothing}
end
function Order(
    orderid::Oid,
    side,
    size,
    price,
    acctid::Aid,
) where {Oid<:Integer,Aid<:Integer}
    Order{Oid,Aid}(orderid, side, size, price, acctid)
end

# Orderbook State Saving Methods

function _order_to_csv(o::Order)
    @sprintf "LMT,%i,%s,%i,%f,%i" o.orderid o.side o.size o.price o.acctid
end


"Return new order with size modified"
copy_modify_size(o::Order{Oid,Aid}, new_size) where {Oid,Aid} =
    Order{Oid,Aid}(o.orderid, o.side, new_size, o.price, o.acctid)

""""
OrderQueue is a queue of orders at a fixed price, implemented as a Deque/Vector.

OrderQueue.queue is a Vector (interpreted as double ended queue). Orders are added and removed via FIFO logic.
OrderQueue also keeps track of its contained volume in shares and orders

OrderQueue(price) Initializes an empty order queue at price
"""
struct OrderQueue{Oid<:Integer,Aid<:Integer}
    price::Float32
    queue::Vector{Order{Oid,Aid}}
    total_volume::Base.RefValue{Int64}
    num_orders::Base.RefValue{Int64}
end

# Initialize empty OrderQueue
function OrderQueue{Oid,Aid}(price::Float32) where {Oid<:Integer,Aid<:Integer}
    OrderQueue{Oid,Aid}(
        price,
        Vector{Order{Oid,Aid}}(),
        Base.RefValue{Int64}(0),
        Base.RefValue{Int64}(0),
    )
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

@inline function _popat_orderid!(
    oq::OrderQueue{Oid,Aid},
    pop_id::Oid,
) where {Oid<:Integer,Aid<:Integer}
    ret_ix = Int64(0)
    for i = 1:length(oq.queue)
        @inbounds if oq.queue[i].orderid == pop_id
            ret_ix = i
            break
        end
    end
    return popat!(oq.queue, ret_ix)
end

function Base.delete!(oq::OrderQueue, orderid::Integer)
    ord = _popat_orderid!(oq, orderid)
    oq.total_volume[] -= ord.size
    oq.num_orders[] -= 1
end

function Base.popfirst!(oq::OrderQueue)
    ord = popfirst!(oq.queue)
    oq.total_volume[] -= ord.size
    oq.num_orders[] -= 1
    return ord
end

Base.isempty(oq::OrderQueue) = Base.isempty(oq.queue)

function Base.print(io::IO, oq::OrderQueue)
    write(io::IO, "OrderQueue @ price=$(oq.price):", "\n")
    # write(io," ","TRD,ID,SIDE,SIZE,PX,ACCT",'\n')
    for ord in oq.queue
        write(io::IO, " ")
        print(io::IO, ord)
        write(io::IO, "\n")
        # write(io::IO," ",_order_to_csv(ord),"\n")
    end
end
