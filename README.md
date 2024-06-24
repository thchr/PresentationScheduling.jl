# PresentationSchedule.jl

Schedule a list of meetings, distributing research and journal club presentations so as to maximize the time-separation between presentations by the same individual.

## Example
```jl
using PresentationScheduling

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
```
The results can be visualized with `show_schedule`:

> ![`show_schedule(individuals, dates, m, cannot_attend)`](example-schedule.png)
