# Temporary fix... just to make tests pass

abstract type AbstractPriceData{Tprice,Tvol} end

const Price = Float64 #Nullable{Float64}
const Volume = Float64 #Nullable{Float64}

null_volume = NaN
