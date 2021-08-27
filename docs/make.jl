using Documenter
using LimitOrderBook

makedocs(
    sitename = "LimitOrderBook",
    format = Documenter.HTML(),
    modules = [LimitOrderBook]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
