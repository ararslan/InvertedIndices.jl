module InvertedIndices

export InvertedIndex, Not

using Base: tail

"""
    InvertedIndex(idx)
    Not(idx)

Construct an inverted index, selecting all indices not in the passed `idx`.

Upon indexing into an array, the `InvertedIndex` behaves like a 1-dimensional
collection of the indices of the array that are not in `idx`. Bounds are
checked to ensure that all indices in `idx` are within the bounds of the array
— even though they are skipped. The `InvertedIndex` behaves like a
1-dimensional collection of its inverted indices. If `idx` spans multiple
dimensions (like a multidimensional logical mask or `CartesianIndex`), then the
inverted index will similarly span multiple dimensions.
"""
struct InvertedIndex{S}
    skip::S
end
const Not = InvertedIndex

# Like Base.LogicalIndex, the InvertedIndexIterator is a pseudo-vector that is
# just used as an iterator and does not support getindex.
struct InvertedIndexIterator{T,S,P} <: AbstractVector{T}
    skips::S
    picks::P
end
InvertedIndexIterator(skips, picks) = InvertedIndexIterator{eltype(picks), typeof(skips), typeof(picks)}(skips, picks)
Base.size(III::InvertedIndexIterator) = (length(III.picks) - length(III.skips),)

@inline Base.iterate(I::InvertedIndexIterator) = iterate(I, (iterate(I.skips), iterate(I.picks)))
Base.iterate(I::InvertedIndexIterator, ::Tuple{Any, Nothing}) = nothing
@inline function Base.iterate(I::InvertedIndexIterator, (skipitr, pickitr))
    while should_skip(skipitr, pickitr)
        skipitr = iterate(I.skips, tail(skipitr)...)
        pickitr = iterate(I.picks, tail(pickitr)...)
        pickitr === nothing && return nothing
    end
    return (pickitr[1], (skipitr, iterate(I.picks, tail(pickitr)...)))
end
Base.collect(III::InvertedIndexIterator) = [i for i in III]

should_skip(::Nothing, ::Any) = false
should_skip(s::Tuple, p::Tuple) = _should_skip(s[1], p[1])
_should_skip(s, p) = s == p
_should_skip(s::Integer, p::CartesianIndex{1}) = s == p.I[1]
_should_skip(s::CartesianIndex{1}, p::Integer) = s.I[1] == p

@inline Base.checkbounds(::Type{Bool}, A::AbstractArray, I::InvertedIndexIterator{<:Integer}) =
    checkbounds(Bool, A, I.skips) && eachindex(IndexLinear(), A) == eachindex(IndexLinear(), I.picks)
@inline Base.checkbounds(::Type{Bool}, A::AbstractArray, I::InvertedIndexIterator) = checkbounds(Bool, A, I.skips) && axes(A) == axes(I.picks)
@inline Base.checkindex(::Type{Bool}, indx::AbstractUnitRange, I::InvertedIndexIterator) = checkindex(Bool, indx, I.skips) && (indx,) == axes(I.picks)
@inline Base.checkindex(::Type{Bool}, inds::Tuple, I::InvertedIndexIterator) = checkindex(Bool, indx, I.skips) && inds == axes(I.picks)

@inline Base.ensure_indexable(I::Tuple{InvertedIndexIterator, Vararg{Any}}) = (collect(I[1]), Base.ensure_indexable(tail(I))...)

Base.show(io::IO, I::InvertedIndexIterator) = show(io, collect(I))

# We use a custom sort method that supports Base.LogicalIndex and CartesianIndex
sort(A::AbstractArray) = Base.sort(A)
sort(A::Union{Number,CartesianIndex,Base.LogicalIndex}) = A

@inline function Base.to_indices(A, inds, I::Tuple{InvertedIndex, Vararg{Any}})
    new_indices = to_indices(A, inds, (I[1].skip, tail(I)...))
    skips = sort(new_indices[1])
    picks = spanned_indices(inds, skips)[1]
    return (InvertedIndexIterator(skips, picks), tail(new_indices)...)
end

struct ZeroDArray{T} <: AbstractArray{T,0}
    x::T
end
Base.size(::ZeroDArray) = ()
Base.getindex(Z::ZeroDArray) = Z.x

# Be careful with CartesianIndex as they splat out to a variable number of new indices and do not iterate
function Base.to_indices(A, inds, I::Tuple{InvertedIndex{<:CartesianIndex}, Vararg{Any}})
    new_indices = to_indices(A, inds, (I[1].skip, tail(I)...))
    skips = ZeroDArray(I[1].skip)
    picks, tails = spanned_indices(inds, skips)
    return (InvertedIndexIterator(skips, picks), to_indices(A, tails, tail(I))...)
end

# Either return a CartesianRange or an axis vector
@inline spanned_indices(inds, ::Any) = inds[1], tail(inds)
const NIdx{N} = Union{CartesianIndex{N}, AbstractArray{CartesianIndex{N}}, AbstractArray{Bool,N}}
@inline spanned_indices(inds, ::NIdx{0}) = CartesianIndices(()), inds
@inline spanned_indices(inds, ::NIdx{1}) = inds[1], tail(inds)
@inline function spanned_indices(inds, ::NIdx{N}) where N
    heads, tails = Base.IteratorsMD.split(inds, Val(N))
    return CartesianIndices(heads), tails
end

# It's possible more indices were specified than there were axes
@inline spanned_indices(inds::Tuple{}, ::Any) = Base.OneTo(1), ()
@inline spanned_indices(inds::Tuple{}, ::NIdx{0}) = CartesianIndices(()), ()
@inline spanned_indices(inds::Tuple{}, ::NIdx{1}) = Base.OneTo(1), ()
@inline spanned_indices(inds::Tuple{}, ::NIdx{N}) where N = CartesianIndices(ntuple(i->Base.OneTo(1), N)), ()

# This is an interesting need — we need this because otherwise indexing with a
# single multidimensional boolean array ends up comparing a multidimensional cartesian
# index to a linear index. Does this need addressing in Base, too?
@inline Base.to_indices(A, I::Tuple{Not{<:NIdx{1}}}) = to_indices(A, (eachindex(IndexLinear(), A),), I)
@inline Base.to_indices(A, I::Tuple{Not{<:NIdx}}) = to_indices(A, axes(A), I)
# Arrays of Bool are even more confusing as they're sometimes linear and sometimes not
@inline Base.to_indices(A, I::Tuple{Not{<:AbstractArray{Bool, 1}}}) = to_indices(A, (eachindex(IndexLinear(), A),), I)
@inline Base.to_indices(A, I::Tuple{Not{<:Union{Array{Bool}, BitArray}}}) = to_indices(A, (eachindex(A),), I)

end # module
