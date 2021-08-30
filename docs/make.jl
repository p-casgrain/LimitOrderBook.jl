push!(LOAD_PATH,"../src/")
using Documenter
using LimitOrderBook


makedocs(
    sitename = "LimitOrderBook",
    modules = [LimitOrderBook],
    format = Documenter.HTML(),
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs( repo = "github.com/p-casgrain/LimitOrderBook.jl/" )
