using AVLTrees

"""
    OneSidedBook{Oid,Aid,ST,PT} 
    
One-Sided book with order-id type Oid, account-id type Aid, 
size type ST and price type PT.

OneSidedBook is a one-sided book (i.e. :BID or :ASK) of order queues at 
varying prices. 

OrderQueues are stored in an AVLTree (.book) indexed 
either by price (:ASK) or -price (:BID)

The book keeps track of various statistics such as the current best price,
total share and price volume, as well as total contained number of orders.

"""
@kwdef mutable struct OneSidedBook{Oid<:Integer,Aid<:Integer,ST<:Real,PT<:Real}
    side::Symbol
    book::AVLTree{PT,OrderQueue{Oid,Aid,ST,PT}} = AVLTree{PT,OrderQueue{Oid,Aid,ST,PT}}()
    total_volume::Int64 = 0 # Total volume available in shares
    num_orders::Int32 = Int32(0) # Number of orders in the book
    best_price::Union{PT,Nothing} = nothing # best bid or ask
end


Base.isempty(sb::OneSidedBook) = isempty(sb.book)

"Updates the latest best price in a Sidebook (either :BID or :ASK book)."
function _update_next_best_price!(sb::OneSidedBook)
    sb.best_price = isempty(sb.book) ? nothing : first(sb.book)[1]
    return
end

"Retrieve order queue from OneSidedBook at given price"
function _get_price_queue(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    price::PT,
) where {Oid,Aid,ST,PT<:Real}
    pricekey = sb.side == :ASK ? price : -price
    AVLTrees.findkey(sb.book, pricekey) # Return the price queue
end

"Delete entire queue associated with given price from OneSidedBook"
function _delete_price_queue!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    price::PT,
) where {Oid,Aid,ST,PT<:Real}
    pricekey = sb.side == :ASK ? price : -price
    price_queue = pop!(sb.book, pricekey) # delete price queue

    # update book stats
    (price_queue.price == sb.best_price) && _update_next_best_price!(sb) # Update price only if best price was changed
    sb.num_orders -= price_queue.num_orders[]
    sb.total_volume -= price_queue.total_volume[]
end


"Insert new_order into OneSidedBook at given price, create new price queue if needed"
function insert_order!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    new_order::Order{Oid,Aid,ST,PT},
) where {Oid,Aid,ST,PT<:Real}
    pricekey = (sb.side == :ASK) ? new_order.price : -new_order.price
    # search for order queue at price
    order_queue = AVLTrees.findkey(sb.book, pricekey)
    if isnothing(order_queue) # If key not present (price doesnt exist in book)
        new_queue = OrderQueue{Oid,Aid,ST,PT}(new_order.price) # Create new price queue
        push!(new_queue, new_order) # Add order to new price queue
        insert!(sb.book, pricekey, new_queue) # add new price queue to OneSidedBook

        # Update new best price depending on bid/ask
        if isnothing(sb.best_price)
            sb.best_price = new_order.price
        elseif sb.side == :BID
            sb.best_price = max(new_order.price, sb.best_price)
        else
            sb.best_price = min(new_order.price, sb.best_price)
        end
    else # If order queue present, retrieve queue and insert new order
        push!(order_queue, new_order)
    end

    # Update Onesidedbook info
    sb.num_orders += 1
    sb.total_volume += new_order.size
end

"Delete order with given price/tick_id from book"
function pop_order!(
    sb::OneSidedBook{Oid,Aid,ST,PT},
    price::PT,
    orderid::Oid,
) where {Oid,Aid,ST<:Real,PT<:Real}
    # Get price queue and delete order from it
    order_queue = _get_price_queue(sb, price)
    Δvolm = order_queue.total_volume[] # get stats before deletion
    ord = popat_orderid!(order_queue, orderid)
    Δvolm -= order_queue.total_volume[] # get stats after deletion

    # If order deletion depleted price queue, delete the whole queue
    if isempty(order_queue)
        _delete_price_queue!(sb, price) # note: this function will update price
    end

    # Update Onesidedbook info
    # TODO, Record change in order queue stats
    sb.num_orders -= 1
    sb.total_volume -= Δvolm

    return ord # return popped order, is nothing if no order found
end

