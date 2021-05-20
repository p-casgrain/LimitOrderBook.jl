
begin # Create (Deterministic) Limit Order Generator
    using Base.Iterators: cycle, take, zip, flatten
    orderid_iter = Base.Iterators.countfrom(1)
    sign_iter = cycle([1,-1,-1,1,1,-1])
    side_iter = ( s>0 ? :ASK : :BID for s in sign_iter )
    spread_iter = cycle([3 2 3 2 2 2 3 2 3 4 2 2 3 2 3 2 3 3 2 2 3 2 5 2 2 2 2 2 4 2 3 6 5 6 3 2 3 5 4]*1e-2)
    price_iter = ( Float32(100.0 + sgn*δ) for (δ,sgn) in zip(spread_iter,sign_iter) )
    size_iter = cycle([2,5,3,4,10,15,1,6,13,11,4,1,5])
    # zip them all together
    lmt_order_info_iter = zip(orderid_iter,price_iter,size_iter,side_iter)
end

begin # Create (Deterministic) Market Order Generator
    mkt_size_iter = cycle([10,20,30,15,25,5,7])
    mkt_side_iter = cycle([:BID,:ASK,:ASK,:BID,:ASK,:BID])
    mkt_order_info_iter = zip(mkt_size_iter,mkt_side_iter)
end

@testset "Submit and Cancel 1" begin # Add and delete all orders, verify book is empty, verify account tracking
    ob = LimitOrderBook.OrderBook() #Initialize empty book
    order_info_lst = take(lmt_order_info_iter,50000)
    # Add a bunch of orders
    for (orderid, price, size, side) in order_info_lst
        LimitOrderBook.submit_limit_order!(ob,orderid,price,size,side,acct_id=10101)
    end
    @test length(ob.acct_map[10101]) == 50000 # Check account order tracking
    # Cancel them all
    for (orderid, price, size, side) in order_info_lst
        LimitOrderBook.cancel_limit_order!(ob,orderid,price,side,acct_id=10101)
    end
    # Check emptiness
    @test isempty(ob.bid_orders)
    @test isempty(ob.ask_orders)
    @test isempty(ob.acct_map[10101])
end

@testset "MO Liquidity Wipe" begin # Wipe out book completely, try MOs on empty book
    ob = LimitOrderBook.OrderBook() #Initialize empty book
    # Add a bunch of orders
    for (orderid, price, size, side) in Base.Iterators.take( lmt_order_info_iter, 50 )
        LimitOrderBook.submit_limit_order!(ob,orderid,price,size,:BID)
    end
    mo_matches, mo_flag = LimitOrderBook.submit_market_order!(ob,:BID,100000)

    # Tests
    @test length( mo_matches ) == 50
    @test mo_flag == :INCOMPLETE
    @test isempty(LimitOrderBook.submit_market_order!(ob,:BID,10000)[1] )
    @test isempty(ob.bid_orders)
    @test isempty(ob.ask_orders)
end

@testset "Order match exact - bid" begin # Test correctness in order matching system / Stat calculation (:BID)
    ob = LimitOrderBook.OrderBook() #Initialize empty book
    # record order book info before
    order_lst_tmp = Base.Iterators.take( Base.Iterators.filter( x-> x[4]==:BID, lmt_order_info_iter), 7 ) |> collect
    
    # Add a bunch of orders
    for (orderid, price, size, side) in order_lst_tmp
        LimitOrderBook.submit_limit_order!(ob,orderid,price,size,:BID)
    end

    # record information from before
    expected_bid_volm_before = sum( x[3] for x in order_lst_tmp )
    expected_bid_n_orders_before =  length(order_lst_tmp)
    

    # execute MO
    mo_matches, mo_flag = LimitOrderBook.submit_market_order!(ob,:BID,30)
    mo_match_sizes = [o.size for o in mo_matches]
    
    # record what is expected to be seen
    expected_bid_volm_after = expected_bid_volm_before - 30
    expected_bid_n_orders_after = expected_bid_n_orders_before - 5
    expected_best_bid_after = Float32(99.97)

    # record what is expected of MO result
    expected_mo_match_size = [5,15,6,1,2,1]
    expected_mo_flag = :COMPLETE
    
    # Compute realized values
    book_info_after = LimitOrderBook.book_depth_info(ob,max_depth=1000)
    realized_bid_volm_after  = sum(book_info_after[:BID][:volume])
    realized_bid_n_orders_after = sum(book_info_after[:BID][:orders])
    realized_best_bid_after = first(book_info_after[:BID][:price])
    
    # Check all expected vs realized values
    @test realized_bid_volm_after == expected_bid_volm_after
    @test realized_bid_n_orders_after == expected_bid_n_orders_after
    @test realized_best_bid_after == expected_best_bid_after
    @test mo_match_sizes == expected_mo_match_size
    @test mo_flag == expected_mo_flag
end



