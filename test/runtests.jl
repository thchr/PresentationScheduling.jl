using Test
using PresentationScheduling

# ---------------------------------------------------------------------------------------- #
# README example

dates = Date("2024-08-28"):Week(2):Date("2024-12-18")
individuals = ["John", "Jane", "Bob", "Alice", "Sven", "Luis", "Jean", "Malcolm"]

presentations_modify = Dict("Malcolm" => 1, "Alice" => 3)
journals_modify = Dict("Malcolm" => 0, "Alice" => 0, "Sven" => 0)
cannot_attend = Dict("Malcolm" => dates[3:end])

m = optimize_presentation_schedule(
    individuals, dates, presentations_modify, journals_modify, cannot_attend;
    default_presentations=2,
    min_total=2,
    max_total=3,
    min_presentations=1,
    max_presentations=3,
    min_journals=0,
    max_journals=1,
    time_limit=20)

@test PresentationScheduling.objective_value(m) < 0.36

# test `show_schedule`
io = IOBuffer()
show_schedule(io, individuals, dates, m, cannot_attend)
s = String(take!(io))
lines = collect(eachline(IOBuffer(s)))
malcolm_row = lines[findfirst(contains("Malcolm"), lines)]
@test count('●', malcolm_row) == 1

# ---------------------------------------------------------------------------------------- #