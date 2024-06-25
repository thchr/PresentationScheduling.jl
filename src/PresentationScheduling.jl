module PresentationScheduling

# ---------------------------------------------------------------------------------------- #

using JuMP
using PrettyTables
using HiGHS
using Dates

# ---------------------------------------------------------------------------------------- #

export optimize_presentation_schedule

export Date, Week # reexport Date & Week from Dates for ease of use

# ---------------------------------------------------------------------------------------- #

include("optimize.jl")
include("show.jl")

# ---------------------------------------------------------------------------------------- #

end # module
