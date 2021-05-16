# Define Order, OrderQueue objects and relavant methods.

"Orders as an immutable container type"
struct Order
    orderid::Int64
    side::Symbol
    size::Int64
    price::Float32
    acctid::Union{Int64,Nothing}
end

OrderRef = RefValue{Order}

# Orderbook State Saving Methods

_order_to_csv(o::Order) = "LMT,$(o.orderid),$(string(o.side)),$(o.size),$(o.price),$(o.acctid)"


"Return new order with size modified"
copy_modify_size(o::Order,size) = Order(o.orderid,o.side,size,o.price,o.acctid)

""""
OrderQueue is a queue of orders at a fixed price, implemented as a Deque/Vector.

OrderQueue.queue is a Vector (interpreted as double ended queue). Orders are added and removed via FIFO logic.
OrderQueue also keeps track of its contained volume in shares and orders

OrderQueue(price) Initializes an empty order queue at price
"""
@kwdef struct OrderQueue
    price::Float32
    queue::Vector{Order} = Vector{Order}()
    total_volume::Base.RefValue{Int64} = Base.RefValue{Int64}(0)
    num_orders::Base.RefValue{Int64} = Base.RefValue{Int64}(0)
end



# Insert, delete, push, pop orders into/out of OrderQueue
function Base.push!(oq::OrderQueue,ord::Order)
    push!(oq.queue,ord)
    oq.total_volume[] += ord.size
    oq.num_orders[] += 1
end

function Base.pushfirst!(oq::OrderQueue,ord::Order)
    pushfirst!(oq.queue,ord)
    oq.total_volume[] += ord.size
    oq.num_orders[] += 1
end

@inline function _popat_orderid!(oq::OrderQueue,pop_id::Int64)
    ret_ix = Int64(0)
    for i in 1:length(oq.queue)
        @inbounds if oq.queue[i].orderid == pop_id
            ret_ix = i
            break
        end
    end
    return popat!(oq.queue,ret_ix)
end

function Base.delete!(oq::OrderQueue,orderid::Int64)
    ord = _popat_orderid!(oq,orderid)
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

function Base.print(io::IO,oq::OrderQueue)
    write(io::IO,"OrderQueue @ price=$(oq.price):","\n")
    # write(io," ","TRD,ID,SIDE,SIZE,PX,ACCT",'\n')
    for ord in oq.queue
        write(io::IO," ")
        print(io::IO,ord)
        write(io::IO,"\n")
        # write(io::IO," ",_order_to_csv(ord),"\n")
    end
end