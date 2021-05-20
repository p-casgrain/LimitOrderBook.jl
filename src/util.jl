using DataStructures: SortedSet
using AVLTrees
import AVLTrees

# Extend AVLTree Functionality w.r.t. base functions
using Base: RefValue, iterate, haskey, getkey, getindex, setindex!, length, 
            eltype, isempty, insert!, popfirst!, @kwdef, insert!, 
            first_index, print

Base.getkey(tr::AVLTree{K,D},k::K) where {K,D} = findkey(tr,k)
Base.getindex(tr::AVLTree{K,D},k::K) where {K,D} = Base.getkey(tr,k) 
Base.setindex!(tr::AVLTree{K,D},k::K,d::D) where {K,D} = AVLTrees.insert!(tr,k,d)
Base.haskey(tr::AVLTree{K,D},k::K) where {K,D} = !(Base.getkey(tr,k) === nothing)
Base.eltype(::AVLTree{K,D}) where {K,D} = D
Base.isempty(tr::AVLTree{K,D}) where {K,D} = isnothing(tr.root)
# Base.length(tr::AVLTree{K,D}) where {K,D} = AVLTrees.size(tr)

function Base.popfirst!(tree::AVLTree)
    # traverse to left-most node
    if isnothing(tree.root)
        return
    end
    node = tree.root
    while !isnothing(node.left)
        node = node.left
    end
    # delete node and return data
    node_data = node.data
    delete!(tree,node)
    return node_data
end

function Base.popat!(tree::AVLTree{K,D},key::K) where {K,D}
    node = AVLTrees.find_node(tree, key)
    if !isnothing(node)
        node_dat = node.data
        delete!(tree, node)
        return node_dat
    else
        return
    end
end

function Base.first_index(tree::AVLTree)
    # traverse to left-most node
    if isnothing(tree.root)
        return
    end
    node = tree.root
    while !isnothing(node.left)
        node = node.left
    end
    # return node key
    return key
end
