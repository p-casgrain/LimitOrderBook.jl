
"""
OneSidedBook is a one-sided book (i.e. :BID or :ASK) of order queues at 
varying prices. 

OrderQueues are stored in an AVLTree (.book) indexed 
either by price (:ASK) or -price (:BID)

The book keeps track of various statistics such as the current best price,
total share and price volume, as well as total contained number of orders.

"""
@kwdef mutable struct OneSidedBook
    side::Symbol
    book::AVLTree{Float32,OrderQueue} = AVLTree{Float32,OrderQueue}()
    total_volume::Int64 = 0 # Total volume available in shares
    num_orders::Int32 = Int32(0) # Number of orders in the book
    best_price::Union{Float32,Nothing} = nothing # best bid or ask
end

Base.isempty(sb::OneSidedBook) = Base.isempty(sb.book)

"Updates the latest best price in a Sidebook (either :BID or :ASK book)."
function _update_next_best_price!(sb::OneSidedBook)
    sb.best_price = isempty(sb.book) ? nothing : first(sb.book)[1]
    return
end

"Retrieve order queue from OneSidedBook at given price"
function _get_price_queue(sb::OneSidedBook,price::Float32)
    pricekey = sb.side == :ASK ? price : -price
    getkey(sb.book,pricekey) # Return the price queue
end

"Delete entire queue associated with given price from OneSidedBook"
function _delete_price_queue!(sb::OneSidedBook,price::Float32)
    pricekey = sb.side == :ASK ? price : -price
    price_queue = popat!(sb.book,pricekey) # delete price queue
    
    # update book stats
    (price_queue.price == sb.best_price) && _update_next_best_price!(sb) # Update price only if best price was changed
    sb.num_orders -= price_queue.num_orders[]
    sb.total_volume -= price_queue.total_volume[]
end


"Insert new_order into OneSidedBook at given price, create new price queue if needed"
function insert_order!(sb::OneSidedBook,new_order::Order)
    pricekey = (sb.side == :ASK) ? new_order.price : -new_order.price
    # search for order queue at price
    order_queue = getkey(sb.book,pricekey)
    if isnothing(order_queue) # If key not present (price doesnt exist in book)
        new_queue = OrderQueue(price=new_order.price) # Create new price queue
        push!(new_queue,new_order) # Add order to new price queue
        insert!(sb.book,pricekey,new_queue) # add new price queue to OneSidedBook

        # Update new best price depending on bid/ask
        if isnothing(sb.best_price)
            sb.best_price = new_order.price
        elseif sb.side == :BID
            sb.best_price = max(new_order.price,sb.best_price)
        else
            sb.best_price = min(new_order.price,sb.best_price)
        end
    else # If order queue present, retrieve queue and insert new order
        push!(order_queue,new_order)
    end

    # Update Onesidedbook info
    sb.num_orders += 1
    sb.total_volume += new_order.size
end

"Delete order with given price/tick_id from book"
function delete_order!(sb::OneSidedBook,price::Float32,orderid::Int64)
    # Get price queue and delete order from it
    order_queue = _get_price_queue(sb,price)
    vol0 = order_queue.total_volume[] # get stats before deletion
    delete!(order_queue,orderid)
    vol1 = order_queue.total_volume[] # get stats after deletion

    # If order deletion depleted price queue, delete the whole queue
    if isempty(order_queue)
        _delete_price_queue!(sb,price) # note: this function will update price
    end

    # Update Onesidedbook info
    # TODO, Record change in order queue stats
    sb.num_orders -= 1
    sb.total_volume -= (vol0-vol1)

end

