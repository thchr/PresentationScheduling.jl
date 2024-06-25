# Plain-text display
function Base.show(io::IO, ::MIME"text/plain", schedule :: PresentationSchedule)
    (; individuals, dates, model, cannot_attend) = schedule
    if termination_status(model) ≠ INFEASIBLE
        x = value.(object_dictionary(model)[:x])
        y = value.(object_dictionary(model)[:y])

        printstyled(io, " ●︎ research presentation  ")
        printstyled(io, "■ journal club  ", color = :blue)
        printstyled(io, "▉ cannot attend\n"; color = :red)

        pretty_table(io, x;
            backend = Val(:text),
            header = [stringify_date(date) for date in dates],
            row_labels = [string(individual) for individual in individuals],
            alignment = :c,
            formatters = (v,i,j) -> v≈1 ? (y[i,j]>0.5 ? "■" : "●︎") : "",
            highlighters = (
                Highlighter((data,i,j) -> y[i,j]>0.5; foreground = :blue),
                Highlighter((data,i,j) -> 
                    is_cannot_attend(data, i, j, individuals, dates, cannot_attend);
                    background = :red)
                )
        )
        print(io, "Objective value (total badness): ", objective_value(model))
    else
        print(io, "No feasible solution found.")
    end
end

# ---------------------------------------------------------------------------------------- #
# HTML

function Base.show(io::IO, ::MIME"text/html", schedule :: PresentationSchedule)
    (; individuals, dates, model) = schedule
    if termination_status(model) ≠ INFEASIBLE
        x = value.(object_dictionary(model)[:x])
        y = value.(object_dictionary(model)[:y])

        pretty_table(io, x;
            backend = Val(:html),
            header = [stringify_date(date) for date in dates],
            row_labels = [string(individual) for individual in individuals],
            alignment = :c,
            formatters = (v,i,j) -> v≈1 ? (y[i,j]>0.5 ? "J" : "R") : "",
        )
    else
        print(io, "<div>No feasible solution found.</div>")
    end
end

# ---------------------------------------------------------------------------------------- #
# Helper utilities

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
