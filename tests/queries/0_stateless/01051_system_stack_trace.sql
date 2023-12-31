SET storage_system_stack_trace_pipe_read_timeout_ms = 1000;

-- { echo }
SELECT count() > 0 FROM system.stack_trace WHERE query_id != '';
-- opimization for not reading /proc/self/task/{}/comm and avoid sending signal
SELECT countIf(thread_id > 0) > 0 FROM system.stack_trace;
-- optimization for trace
SELECT count(trace) > 0 FROM system.stack_trace WHERE length(trace) > 0 LIMIT 1;
-- optimization for query_id
SELECT length(query_id) > 0 FROM system.stack_trace WHERE query_id != '' LIMIT 1;
-- optimization for thread_name
SELECT length(thread_name) > 0 FROM system.stack_trace WHERE thread_name != '' LIMIT 1;
-- enough rows (optimizations works "correctly")
SELECT count() > 100 FROM system.stack_trace;
