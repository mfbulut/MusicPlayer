package main

import "core:fmt"
import "core:time"

Profiler :: struct {
	start_time:        time.Time,
	last_section_time: time.Time,
	section_times:     map[string]time.Duration,
	total_time:        time.Duration,
}

profiler: Profiler

start_profiling :: proc() {
	profiler.start_time = time.now()
	profiler.last_section_time = profiler.start_time
	clear(&profiler.section_times)
}

profile_section :: proc(name: string) {
	current_time := time.now()
	duration := time.diff(profiler.last_section_time, current_time)
	profiler.section_times[name] = duration
	profiler.last_section_time = current_time
}

end_profiling :: proc() {
	profiler.total_time = time.since(profiler.start_time)

	fmt.println("=== Frame Profiling Results ===")
	fmt.printf("Total frame time: %.3f ms\n", time.duration_milliseconds(profiler.total_time))

	for name, duration in profiler.section_times {
		percentage := f64(duration) / f64(profiler.total_time) * 100
		fmt.printf(
			"%-25s: %6.3f ms (%5.1f%%)\n",
			name,
			time.duration_milliseconds(duration),
			percentage,
		)
	}
	fmt.println("===============================")
}
