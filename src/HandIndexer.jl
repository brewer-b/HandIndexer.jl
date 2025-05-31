module HandIndexer

export round_size, hand_index, hand_unindex, hand_unindex!,
        perfect_recall, imperfect_recall, flop_recall, imperfect_board_recall

using HandIndexer_jll, PlayingCards
import Base.@propagate_inbounds

const lib = HandIndexer_jll.HandIndexer

function __init__()
    @ccall lib.hand_index_ctor()::Cvoid
    perfect_recall[] = HandIndexers([[2],[2,3],[2,3,1],[2,3,1,1]])
    imperfect_recall[] = HandIndexers([[2],[2,3],[2,4],[2,5]])
    flop_recall[] = HandIndexers([[2],[2,3],[2,3,1],[2,3,2]])
    imperfect_board_recall[] = HandIndexers([[1],[3],[4],[5]])
end

mutable struct hand_indexer_t end
mutable struct Indexer
    ptr::Ptr{hand_indexer_t}
    function Indexer(ptr::Ptr{hand_indexer_t})
        if ptr == C_NULL
            error("hand_indexer_init returned C_NULL, failed to create indexer.")
        end
        obj = new(ptr)
        finalizer(free_indexer, obj)
        return obj
    end
end

function create_indexer(cards_per_round)
    cards_per_round_u8 = UInt8.(cards_per_round)
    ptr = @ccall lib.hand_indexer_init(length(cards_per_round_u8)::UInt32, cards_per_round_u8::Ptr{UInt8})::Ptr{hand_indexer_t}
    return ptr
end

function free_indexer(indexer)
    @ccall lib.hand_indexer_free(indexer.ptr::Ptr{hand_indexer_t})::Cvoid
end

struct HandIndexers
    cards_per_round_per_round::Vector{Vector{UInt8}}
    indexers::Vector{Indexer}
end

function HandIndexers(cards_per_round_per_round)
    u8_cards = [UInt8.(cards_per_round) for cards_per_round in cards_per_round_per_round]
    indexers = [Indexer(create_indexer(cards_per_round)) for cards_per_round in cards_per_round_per_round]
    return HandIndexers(u8_cards, indexers)
end

const perfect_recall = Ref{HandIndexers}()
const imperfect_recall = Ref{HandIndexers}()
const flop_recall = Ref{HandIndexers}()
const imperfect_board_recall = Ref{HandIndexers}()

@propagate_inbounds function round_size(indexer_ref, round)
    indexer = indexer_ref[]
    ptr = indexer.indexers[round].ptr
    r = length(indexer.cards_per_round_per_round[round]) - 1
    return @ccall lib.hand_indexer_size(ptr::Ptr{hand_indexer_t}, r::UInt32)::UInt64
end

const cards_g = [Vector{UInt8}(undef, 52 + 64) for _ in 1:Threads.nthreads()]

@propagate_inbounds function hand_index(indexer_ref, round, cards::Vector{Card})
    thread = Threads.threadid()
    thread_cards_buffer = cards_g[thread]
    num_cards = length(cards)
    for i in 1:num_cards
        thread_cards_buffer[i] = cards[i].val - 1
    end
    indexer = indexer_ref[]
    ptr = indexer.indexers[round].ptr
    return 1 + @ccall lib.hand_index_last(ptr::Ptr{hand_indexer_t}, thread_cards_buffer::Ptr{UInt8})::UInt64
end

@propagate_inbounds function hand_unindex!(indexer_ref, round, index, output::Vector{Card})
    indexer = indexer_ref[]
    ptr = indexer.indexers[round].ptr
    r = length(indexer.cards_per_round_per_round[round]) - 1
    result = @ccall lib.hand_unindex(ptr::Ptr{hand_indexer_t}, r::UInt32, (index-1)::UInt64, output::Ptr{UInt8})::Cuchar
    @assert(result > 0)
    for i in 1:length(output)
        output[i] = Card(output[i].val + 1)
    end
    return nothing
end

@propagate_inbounds function hand_unindex(indexer_ref, round, index)
    indexer = indexer_ref[]
    num_cards = sum(indexer.cards_per_round_per_round[round])
    hand = Vector{Card}(undef, num_cards)
    hand_unindex!(indexer_ref, round, index, hand)
    return hand
end

end # module HandIndexer
