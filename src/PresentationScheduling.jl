module PresentationScheduling

using JuMP
using PrettyTables
using HiGHS
using Dates

# ---------------------------------------------------------------------------------------- #

export optimize_presentation_schedule
export show_schedule

export Date, Week # reexport Date & Week from Dates for ease of use

# ---------------------------------------------------------------------------------------- #

function badness(date :: Int, date′ :: Int)
    return inv(abs(date - date′))
end

function badness(date :: Date, date′ :: Date)
    dist = abs(date - date′).value # in days
    return inv(dist)
end

"""
    optimize_presentation_schedule(
        individuals :: AbstractVector{Itype},
        dates :: AbstractVector{Dtype},
        [presentations_modify, journals_modify, cannot_attend]...; 
        kwargs...
        ) where {Itype <: Union{Int, String}, Dtype <: Union{Date, Int}}

Given iterables of `individuals` and `dates`, plan a meeting schedule which allocates
research presentations and journal club presentations to each presentation date across
individuals, aiming to space out the presentations of each individual evenly.

Returns a JuMP `Model` whose variables encode an optimized schedule. The schedule can be
displayed via [`show_schedule`](@ref).

## Optional arguments
- `presentations_modify :: Dict{Itype, Int}`: each individual is scheduled to present
  `default_presentations` research presentations (see Keyword arguments). To override this,
  add a `key=>value` pair to `presentation_modify` for the individual.
  E.g., `presentations_modify = Dict("Individual A" => 1)`.
- `journals_modify :: Dict{Itype, Int}`: same as `presentations_modify` but to override the
  number of journal club presentations for specific individuals.
- `cannot attend :: Dict{Itype, <:AbstractVector{Dtype}}`: a list of dates, overlapping with
  those in `dates`, one which a specific individual is unable to present.
  E.g., `cannot_attend = Dict("Individual A" => Date("21/01/2024"))`.

Optional arguments default to empty containers if unspecified.

## Keyword arguments
- `default_presentations :: Int` (default, `2`):
  default number of research presentations per individual; overridable via the optional
  argument `presentations_modify`.
- `default_journals :: Int` (default, `1`):
  default number of journal club presentations per individual; overridable via the optional
  argument `journals_modify`.  
- `min_total :: Int` (default, `2`):
  minimum number of total presentations (research _and_ journal club) per meeting date.
- `max_total :: Int` (default, `4`):
  maximum number of total presentations (research _and_ journal club) per meeting date.
- `min_presentations :: Int` (default, `1`):
  minimum number of research presentations per meeting date.
- `max_presentations :: Int` (default, `3`):
  maximum number of research presentations per meeting date.
- `min_journals :: Int` (default, `0`):
  minimum number of journal club presentations per meeting date.
- `max_journals :: Int` (default, `1`):
  maximum number of journal club presentations per meeting date.
- `time_limit :: Real` (default, `60`):
  time limit imposed on optimizer in seconds; note that a provably optimal schedule usually
  is impractically slow to compute.
"""
function optimize_presentation_schedule(
    individuals           :: AbstractVector{Itype},
    dates                 :: AbstractVector{Dtype},
    presentations_modify  :: Dict{Itype, Int} = Dict{Itype, Int}(),
    journals_modify       :: Dict{Itype, Int} = Dict{Itype, Int}(),
    cannot_attend         :: Dict{Itype, <:AbstractVector{Dtype}} = Dict{Itype, Vector{Dtype}}();
    default_presentations :: Int = 2,
    default_journals      :: Int = 1,
    min_total             :: Int = 2,
    max_total             :: Int = 4,
    min_presentations     :: Int = 1,
    max_presentations     :: Int = 3,
    min_journals          :: Int = 0,
    max_journals          :: Int = 1,
    time_limit            :: Real = 60.0
    ) where {Itype <: Union{Int, String}, Dtype <: Union{Date, Int}}
    

    D = length(dates)
    I = length(individuals)

    # we formulate the optimization as a MIP problem and pick the HiGHS optimizer
    m = Model(optimizer_with_attributes(HiGHS.Optimizer, 
        "random_seed" => abs(rand(Int32)),
        "time_limit" => float(time_limit)))

    # we want to solve a MIQP problem, but there are few good MIQP solvers (and e.g. SCIP
    # which does solve MIQP problems appears slower than the following) - so we rewrite as a
    # MIP problem by introducing auxiliary variables x²[i,d,d′]. We use the HiGHS solver to
    # solve the resulting MIP problem; it seems to fare better than Cbc - solvers like
    # CPLEX or Gurobi would likely be even better, but are not free.
    @variables(m, begin x[i=1:I, d=1:D], Bin end) # presentation encoding
    @variables(m, begin x²[i=1:I, d=1:D, p=1:D], Bin end)
    @variables(m, begin y[i=1:I, d=1:D], Bin end) # journal club modifier encoding

    # x²[i,d,d′] is a linearization of the term x[i,d]*x[i,d′], implemented via constraints
    total_badness = sum(x²[i,d,d′]*badness(dates[d], dates[d′])
                                             for d in 1:D for d′ in d+1:D for i in 1:I)
    @objective(m, Min, total_badness)
    foreach(1:I) do i
        # all persons must present `default_presentation_count` (or whatever is in 
        # `presentation_modifiers`) times
        individual = individuals[i]
        presentations = get(presentations_modify, individual, default_presentations)
        journals      = get(journals_modify, individual, default_journals)
        @constraint(m, sum(x[i,d] for d in 1:D) == presentations + journals)
        @constraint(m, sum(y[i,d] for d in 1:D) == journals)
    end
    foreach(1:D) do d
        # each seminar date has constraints on how many of each kind of presentation there
        # is at least and at most
        @constraint(m, sum(x[i,d] for i in 1:I) ≤ max_total)
        @constraint(m, sum(x[i,d] for i in 1:I) ≥ min_total)
        @constraint(m, sum(x[i,d]-y[i,d] for i in 1:I) ≤ max_presentations)
        @constraint(m, sum(x[i,d]-y[i,d] for i in 1:I) ≥ min_presentations)
        @constraint(m, sum(y[i,d] for i in 1:I) ≤ max_journals)
        @constraint(m, sum(y[i,d] for i in 1:I) ≥ min_journals)
    end
    # force x²[i,d,d′] = x[i,d]*x[i,d′]; standard binary linearization trick
    for i in 1:I, d in 1:D, d′ in 1:D
        if d′ > d
            @constraint(m, x²[i,d,d′] ≤ x[i,d])
            @constraint(m, x²[i,d,d′] ≤ x[i,d′])
            @constraint(m, x²[i,d,d′] ≥ x[i,d] + x[i,d′] - 1)
        else
            @constraint(m, x²[i,d,d′] == 0) # effectively removes these variables; not used
        end
    end

    # constrain journal club modifier `y` so that it can only be "active" if `x` is true
    for i in 1:I
        for d in 1:D
            @constraint(m, y[i,d] ≤ x[i,d])
        end
    end

    # individuals might be unable to attend on certain dates; specified in `cannot_attend`
    for (i, individual) in enumerate(individuals)
        haskey(cannot_attend, individual) || continue
        absence_dates = cannot_attend[individual]
        for (d, date) in enumerate(dates)
            if any(==(date), absence_dates)
                @constraint(m, x[i,d] == 0)
            end
        end
    end

    optimize!(m) # find a feasible solution

    return m
end

function stringify_date(date)
    date isa Date ? string(day(date)) * "/" * string(month(date)) : string(date)
end
function is_cannot_attend(data, i, j, individuals, dates, cannot_attend)
    cannot_attend == nothing && return false
    individual = individuals[i]
    haskey(cannot_attend, individual) || return false

    date = dates[j]
    absence_dates = cannot_attend[individual]
    return any(==(date), absence_dates)
end
"""
    show_schedule([io :: IO], individuals, dates, m, [cannot_attend]; backend)

Given an optimized model `m`, and associated iterables of `individuals` and `dates`, print
the associated schedule to `io` (default, `stdout`) as a table.

The table can optionally be printed as HTML by setting the keyword argument `backend` to
`Val(:html)` (default: `Val(:text)`).
"""
function show_schedule(
            io::IO, individuals, dates, m, cannot_attend=nothing;
            backend=Val(:text))
    if termination_status(m) ≠ INFEASIBLE
        x = value.(object_dictionary(m)[:x])
        y = value.(object_dictionary(m)[:y])

        printstyled(io, " ●︎ research presentation  ")
        printstyled(io, "■ journal club  ", color = :blue)
        printstyled(io, "▉ cannot attend\n"; color = :red)

        highlighters = if backend == Val(:text)
            (
            Highlighter((data,i,j) -> y[i,j]>0.5; foreground = :blue),
            Highlighter((data,i,j) -> is_cannot_attend(data, i, j, individuals, dates, cannot_attend); background = :red)
            )
        else
            Tuple{}()
        end
        pretty_table(io, x;
            backend = backend,
            header = [stringify_date(date) for date in dates],
            row_labels = [string(individual) for individual in individuals],
            alignment = :c,
            formatters = (v,i,j) -> v≈1 ? (y[i,j]>0.5 ? "■" : "●︎") : "",
            highlighters = highlighters
        )
        print(io, "Objective value (total badness): ", objective_value(m))
    else
        print(io, "No feasible solution found.")
    end
end
function show_schedule(individuals, dates, m, cannot_attend=nothing; kws...)
    show_schedule(stdout, individuals, dates, m, cannot_attend=nothing; kws...)
end

end # module
