

begin # Create (Deterministic) Limit Order Generator
    MyOrderSubTypes = (Int64,Float32,Int64,Int64) # define types for Order Size, Price, Order IDs, Account IDs
    MyOrderType = Order{MyOrderSubTypes...}
    MyLOBType = OrderBook{MyOrderSubTypes...}
    using Base.Iterators: cycle, take, zip, flatten
    orderid_iter = Base.Iterators.countfrom(1)
    sign_iter = cycle([1,-1,-1,1,1,-1])
    side_iter = ( s>0 ? SELL_ORDER : BUY_ORDER for s in sign_iter )
    spread_iter = cycle([3 2 3 2 2 2 3 2 3 4 2 2 3 2 3 2 3 3 2 2 3 2 5 2 2 2 2 2 4 2 3 6 5 6 3 2 3 5 4]*1e-2)
    price_iter = ( Float32(100.0 + sgn*δ) for (δ,sgn) in zip(spread_iter,sign_iter) )
    size_iter = cycle([2,5,3,4,10,15,1,6,13,11,4,1,5])
    # zip them all together
    lmt_order_info_iter = zip(orderid_iter,price_iter,size_iter,side_iter)
end

begin # Create (Deterministic) Market Order Generator
    mkt_size_iter = cycle([10,20,30,15,25,5,7])
    mkt_side_iter = cycle([SELL_ORDER,BUY_ORDER,BUY_ORDER,SELL_ORDER,BUY_ORDER,SELL_ORDER])
    mkt_order_info_iter = zip(mkt_size_iter,mkt_side_iter)
end

@testset "Submit and Cancel 1" begin # Add and delete all orders, verify book is empty, verify account tracking
    ob = MyLOBType() #Initialize empty book
    order_info_lst = take(lmt_order_info_iter,50000)
    # Add a bunch of orders
    for (orderid, price, size, side) in order_info_lst
        submit_limit_order!(ob,orderid,side,price,size,10101)
    end
    @test length(ob.acct_map[10101]) == 50000 # Check account order tracking
    # Cancel them all
    for (orderid, price, size, side) in order_info_lst
        cancel_order!(ob,orderid,price,side)
    end
    # Check emptiness
    @test isempty(ob.bid_orders)
    @test isempty(ob.ask_orders)
    @test isempty(ob.acct_map[10101])
end

@testset "MO Liquidity Wipe" begin # Wipe out book completely, try MOs on empty book
    ob = MyLOBType() #Initialize empty book
    # Add a bunch of orders
    for (orderid, price, size, side) in Base.Iterators.take( lmt_order_info_iter, 50 )
        submit_limit_order!(ob,orderid,BUY_ORDER,price,size)
    end
    mo_matches, mo_ltt = submit_market_order!(ob,SELL_ORDER,100000)

    # Tests
    @test length( mo_matches ) == 50
    @test mo_ltt > 0
    @test isempty(submit_market_order!(ob,SELL_ORDER,10000)[1] )
    @test isempty(ob.bid_orders)
    @test isempty(ob.ask_orders)
end

@testset "Order match exact - bid" begin # Test correctness in order matching system / Stat calculation (:BID)
    ob = MyLOBType() #Initialize empty book
    # record order book info before
    order_lst_tmp = Base.Iterators.take( Base.Iterators.filter( x-> x[4]===BUY_ORDER, lmt_order_info_iter), 7 ) |> collect
    
    # Add a bunch of orders
    for (orderid, price, size, side) in order_lst_tmp
        submit_limit_order!(ob,orderid,side,price,size)
    end

    orders_before = Iterators.flatten(q.queue for (k,q) in ob.bid_orders.book) |> collect

    # record information from before
    expected_bid_volm_before = sum( x[3] for x in order_lst_tmp )
    expected_bid_n_orders_before =  length(order_lst_tmp)
    

    # execute MO
    mo_matches, mo_ltt = submit_market_order!(ob,SELL_ORDER,30)
    mo_match_sizes = [o.size for o in mo_matches]
    
    # record what is expected to be seen
    expected_bid_volm_after = expected_bid_volm_before - 30
    expected_bid_n_orders_after = expected_bid_n_orders_before - 5
    expected_best_bid_after = Float32(99.97)

    # record what is expected of MO result
    expected_mo_match_size = [5,15,6,1,2,1]
    
    # Compute realized values
    book_info_after = book_depth_info(ob,max_depth=1000)
    realized_bid_volm_after  = sum(book_info_after[:BID][:volume])
    realized_bid_n_orders_after = sum(book_info_after[:BID][:orders])
    realized_best_bid_after = first(book_info_after[:BID][:price])
    
    # Check all expected vs realized values
    @test realized_bid_volm_after == expected_bid_volm_after
    @test realized_bid_n_orders_after == expected_bid_n_orders_after
    @test realized_best_bid_after == expected_best_bid_after
    @test mo_match_sizes == expected_mo_match_size
    @test mo_ltt == 0
end


@testset "Test MO, LO insert, LO cancel outputs" begin
    ob = MyLOBType() #Initialize empty book
    order_info_lst = take(lmt_order_info_iter,500)
    # Add a bunch of orders
    for (orderid, price, size, side) in order_info_lst
        submit_limit_order!(ob,orderid,side,price,size)
    end

    # Test that inserting LO returns correctly
    lmt_info = (10_000, BUY_ORDER, 99.97f0, 3,)
    lmt_obj, _, _ = submit_limit_order!(ob,lmt_info...)
    @test lmt_info[1:4] == (lmt_obj.orderid,lmt_obj.side,lmt_obj.price,lmt_obj.size)

    # Add something on top
    submit_limit_order!(ob, 10_001, BUY_ORDER, 100.02f0, 900,)

    # Test that cancelling present order returns correctly
    lmt_obj_cancel = cancel_order!(ob,lmt_obj)
    @test lmt_obj_cancel == lmt_obj

    # Test that missing order returns correctly
    lmt_obj_cancel_2 = cancel_order!(ob,lmt_obj_cancel)
    @test isnothing(lmt_obj_cancel_2)

    # Test that complete MO returns correctly
    mo_match_list, mo_ltt = submit_market_order!(ob,SELL_ORDER,100)
    @test typeof(mo_match_list) <: Vector{<:Order}
    @test mo_ltt == 0

    mo_match_list, mo_ltt = submit_market_order!(ob,BUY_ORDER,797+13)
    @test length(mo_match_list) == 128
    @test mo_ltt == 13

    mo_match_list, mo_ltt = submit_market_order!(ob,BUY_ORDER,13)
    @test isempty(mo_match_list)
    @test mo_ltt == 13


end

@testset "Test Account Tracking" begin
    ob = MyLOBType() #Initialize empty book

    # Add a bunch of orders
    for (orderid, price, size, side) in take(lmt_order_info_iter,100)
        submit_limit_order!(ob,orderid,side,price,size)
    end
    
    # Add order with an account ID
    acct_id = 1313
    order_id0 = 10001
    my_acct_orders = MyOrderType[]
    push!(my_acct_orders,submit_limit_order!(ob,order_id0,SELL_ORDER,100.03f0,50,acct_id)[1])
    push!(my_acct_orders,submit_limit_order!(ob,order_id0+1,BUY_ORDER,99.98f0,20,acct_id)[1])
    push!(my_acct_orders,submit_limit_order!(ob,order_id0+2,BUY_ORDER,99.97f0,30,acct_id)[1])

    # Throw some more nameless orders on top
    for (orderid, price, size, side) in take(lmt_order_info_iter,20)
        submit_limit_order!(ob,orderid,side,price,size)
    end

    # Get account list from book
    book_acct_list = collect(get_acct(ob,acct_id))
    @test (order_id0 .+ collect(0:2)) == [first(x) for x in book_acct_list] # Test correct ids
    @test my_acct_orders == [last(x) for x in book_acct_list] # Test correct orders
    @test isnothing(get_acct(ob,0))

    # Delete some orders and maintain checks
    to_canc = popat!(my_acct_orders,2)
    canc_order = cancel_order!(ob,to_canc)
    @test to_canc == canc_order
    book_acct_list = collect(get_acct(ob,acct_id))
    @test to_canc ∉ book_acct_list

end


# using BenchmarkTools
# # Add a bunch of orders

# ob = MyLOBType() #Initialize empty book

# order_info_lst = take(lmt_order_info_iter,Int64(10_000)) |> collect
# for (orderid, price, size, side) in order_info_lst
#     submit_limit_order!(ob,orderid,side,price,size)
# end

# (orderid, price, size, side), _ =  Iterators.peel(lmt_order_info_iter)
# @benchmark submit_limit_order!($ob,$orderid,$side,$price,$size,)
# @benchmark (submit_market_order!($ob,BUY_ORDER,1000);)

# @code_typed submit_limit_order!(ob,orderid,side,price,size)