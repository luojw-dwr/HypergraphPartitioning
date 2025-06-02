using Dates 
using Metis
using SparseArrays
using LightGraphs, Graphs

#=
const METIS_NOPTIONS = 40
const METIS_OPTION_NUMBERING = 17
const options = fill(Cint(-1), METIS_NOPTIONS)
options[Int(METIS_OPTION_NUMBERING)+1] = 1

struct Graph
    nvtxs::idx_t
    xadj::Vector{idx_t}
    adjncy::Union{Vector{idx_t}, Ptr{Nothing}}
    vwgt::Union{Vector{idx_t}, Ptr{Nothing}}
    adjwgt::Union{Vector{idx_t}, Ptr{Nothing}}
    function Graph(nvtxs, xadj, adjncy, vwgt=C_NULL, adjwgt=C_NULL)
        return new(nvtxs, xadj, adjncy, vwgt, adjwgt)
    end
end

function graph(G::SparseMatrixCSC; weights::Bool=false, check_hermitian::Bool=true)
    if check_hermitian
        ishermitian(G) || throw(ArgumentError("matrix must be Hermitian"))
    end
    N = size(G, 1)
    xadj = Vector{idx_t}(undef, N+1)
    xadj[1] = 1
    adjncy = Vector{idx_t}(undef, nnz(G))
    vwgt = C_NULL # TODO: Vertex weights could be passed as input argument
    adjwgt = weights ? Vector{idx_t}(undef, nnz(G)) : C_NULL
    adjncy_i = 0
    @inbounds for j in 1:N
        n_rows = 0
        for k in G.colptr[j] : (G.colptr[j+1] - 1)
            i = G.rowval[k]
            i == j && continue # skip self edges
            n_rows += 1
            adjncy_i += 1
            adjncy[adjncy_i] = i
            if weights
                adjwgt[adjncy_i] = G.nzval[k]
            end
        end
        xadj[j+1] = xadj[j] + n_rows
    end
    resize!(adjncy, adjncy_i)
    weights && resize!(adjwgt, adjncy_i)
    return Graph(idx_t(N), xadj, adjncy, vwgt, adjwgt)
end

function metis_partition(G::SimpleWeightedGraph, nparts::Int64, ubfactor::Cfloat; alg = :KWAY)
    G_metis = graph(G.weights)
    part = Vector{Int32}(undef, G.nvtxs)
    nparts == 1 && return fill!(part, 1)
    edgecut = fill(Int32(0), 1)
    ubvec = fill(Float32(ubfactor), nparts)
    if alg == :RECURSIVE
        Metis.METIS_PartGraphRecursive(Ref{Int32}(G.nvtxs), Ref{Int32}(1), G.xadj, G.adjncy, G.vwgt, C_NULL, G.adjwgt,
                                Ref{Int32}(nparts), C_NULL, C_NULL, options, edgecut, part)
    elseif alg == :KWAY
        Metis.METIS_PartGraphKway(Ref{Int32}(G.nvtxs), Ref{Int32}(1), G.xadj, G.adjncy, G.vwgt, C_NULL, G.adjwgt,
                            Ref{Int32}(nparts), C_NULL, C_NULL, options, edgecut, part)
    else
        throw(ArgumentError("unknown algorithm $(repr(alg))"))
    end
    return part
end
=#

function julia_metis_partition(tree::SimpleWeightedGraph,
                                num_parts::Int,
                                ub_factor::Int)
    if num_parts > 2 
        return Metis.partition(tree, num_parts, alg=:KWAY)
    else
        return Metis.partition(tree, num_parts, alg=:RECURSIVE)
    end
end

function build_metis_graph(tree::SimpleWeightedGraph, 
                         metis_opts::Int)
    file_name = source_dir * "/" * "metis_graph" * string(metis_opts) * "." * string(Dates.now()) * ".gr"
    f = open(file_name, "w")
    wts = tree.weights
    println(f, SimpleWeightedGraphs.nv(tree), " ", SimpleWeightedGraphs.ne(tree), " 001")

    for i in 1:SimpleWeightedGraphs.nv(tree)
        nbrs = SimpleWeightedGraphs.Graphs.neighbors(tree, i)
        for j in eachindex(nbrs)
            nbr_vtx = nbrs[j]
            wt = Int(wts[i, nbr_vtx])
            print(f, nbr_vtx, " ", wt, " ")
        end
        print(f, "\n")
    end
    close(f)
    return file_name
end

function metis(metis_path::String, 
            graph_file::String, 
            num_parts::Int, 
            seed::Int, 
            ub_factor::Int,
            metis_opts::Int)
    log_file = source_dir * "metis" * string(metis_opts) * "." * string(Dates.now()) * ".log.txt"
    metis_script = metis_path * "/" * "metis_script.sh" * " " * graph_file * " " * string(num_parts) * " " * string(ub_factor) * " " * string(seed) * " " * log_file
    metis_command = `sh -c $metis_script`
    run(metis_command, wait=true)
    #exit()
    rm_cmd = "rm -r " * log_file
    run(`sh -c $rm_cmd`, wait=true)
    rm_cmd = "rm -r " * graph_file
    run(`sh -c $rm_cmd`, wait=true)
end
