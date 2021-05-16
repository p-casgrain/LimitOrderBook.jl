struct Ticker
    currency::String
    last::Real
    timestamp::DateTime
    volume::Dict{String,Any}
    bid::Real
    ask::Real
    high::Real
    low::Real
    Ticker(currency::String,
           last::Real,
           timestamp::DateTime,
           volume::Dict{String,Any},
           bid::Real,
           ask::Real,
           high::Real,
           low::Real) = new(currency, last,
                                     timestamp, volume,
                                     bid, ask, high, low)
end
