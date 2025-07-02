#!/usr/bin/env bats

setup_file() {
   export THAPI_HOME=$PWD
   export IPROF=$THAPI_BIN_DIR/iprof
   export MPIRUN=${MPIRUN:-mpirun}
}

teardown_file() {
   rm -rf $THAPI_HOME/thapi-traces
}

@test "default_summary" {
   $IPROF $THAPI_TEST_BIN
}

@test "default_trace" {
   $IPROF -t $THAPI_TEST_BIN | wc -l
}

@test "default_timeline" {
   $IPROF -l -- $THAPI_TEST_BIN
   rm out.pftrace
}

@test "archive_summary" {
   $IPROF --archive $THAPI_TEST_BIN
}

@test "replay_summary" {
   $IPROF $THAPI_TEST_BIN
   $IPROF -r
}

@test "no-analysis_all" {
   $IPROF --no-analysis -- $THAPI_TEST_BIN
   $IPROF -r 
   $IPROF -t -r | wc -l
   $IPROF -l -r
   rm out.pftrace 
}

@test "trace-output_all" {
   $IPROF --trace-output trace_1 -- $THAPI_TEST_BIN
   $IPROF -r trace_1
   rm -rf trace_1

   $IPROF --trace-output trace_2 -t -- $THAPI_TEST_BIN | wc -l
   $IPROF -t -r trace_2 | wc -l
   rm -rf trace_2

   $IPROF --trace-output trace_3 -l -- $THAPI_TEST_BIN
   $IPROF -l -r trace_3
   rm -rf trace_3 out.pftrace
}

@test "timeline_output" {
   $IPROF -l roger -- $THAPI_TEST_BIN
   rm roger
}

# Assert Failure
@test "replay_negative" {
   $IPROF  -- $THAPI_TEST_BIN
   run $IPROF -t -r
   [ "$status" != 0 ]
   run $IPROF -l -r
   [ "$status" != 0 ]

   $IPROF -l -- $THAPI_TEST_BIN
   run $IPROF -t -r
   [ "$status" != 0 ]
   rm out.pftrace
}

@test "exit_code_propagated" {
   run $IPROF -- bash -c "exit 55"
   [ "$status" == 55 ]

   run $IPROF --no-analysis -- bash -c "exit 55"
   [ "$status" == 55 ]
}

@test "read_stdin" {
   echo "FOO" | $IPROF cat
}

@test "thapi_toggle" {
  cc -I${THAPI_INC_DIR} ./integration_tests/thapi_toggle.c -o thapi_toggle \
    -Wl,-rpath,${THAPI_LIB_DIR} -L${THAPI_LIB_DIR} -lThapi
  $IPROF --trace-output trace_toggle --no-analysis -- ./thapi_toggle

  start_count=`babeltrace2 trace_toggle | grep lttng_ust_toggle:start | wc -l`
  [ "$start_count" -eq 1 ]

  stop_count=`babeltrace2 trace_toggle | grep lttng_ust_toggle:stop | wc -l`
  [ "$stop_count" -eq 2 ]
}

toggle_count_traces() {
  trace_metadata_file=`find toggle_traces -iname metadata`
  trace_metadata_dir=$(dirname "${trace_metadata_file}")

  traces=$(babeltrace2 --plugin-path=${THAPI_LIB_DIR} \
    --component source:source.ctf.fs --params "inputs=[\"${trace_metadata_dir}\"]" \
    --component=filter:filter.metababel_filter.btx \
    --component=sink:sink.text.pretty)
  rm -rf toggle_traces

  echo $traces | sed -e "s/ \[/@[/g" | sed "s/@/\n/g" | grep . | wc -l
}

@test "toggle_plugin_mpi_np_1" {
  mpicc -I${THAPI_INC_DIR} ./integration_tests/thapi_toggle_mpi.c -o thapi_toggle_mpi \
    -Wl,-rpath,${THAPI_LIB_DIR} -L${THAPI_LIB_DIR} -lThapi

  THAPI_SYNC_DAEMON=fs THAPI_JOBID=0 timeout 40s $MPIRUN -n 1 $IPROF --trace-output toggle_traces --no-analysis -- ./thapi_toggle_mpi 0
  count_0=$(toggle_count_traces)

  THAPI_SYNC_DAEMON=fs THAPI_JOBID=0 timeout 40s $MPIRUN -n 1 $IPROF --trace-output toggle_traces --no-analysis -- ./thapi_toggle_mpi 1
  count_1=$(toggle_count_traces)

  THAPI_SYNC_DAEMON=fs THAPI_JOBID=0 timeout 40s $MPIRUN -n 1 $IPROF --trace-output toggle_traces --no-analysis -- ./thapi_toggle_mpi 2
  count_2=$(toggle_count_traces)

  [ "$count_2" -eq 0 ]
  [ "$count_0" -gt "$count_1" ]
}

toggle_count_vpids() {
  vpids=$(babeltrace2 toggle_traces | sed -e "s/, { vpid = /\nvpid,/g" | grep vpid | awk '{ split($0,a,","); print a[2] }' | sort | uniq | wc -l)
  rm -rf toggle_traces
  echo $vpids
}

@test "toggle_plugin_mpi_np_2" {
  mpicc -I${THAPI_INC_DIR} ./integration_tests/thapi_toggle_mpi.c -o thapi_toggle_mpi \
    -Wl,-rpath,${THAPI_LIB_DIR} -L${THAPI_LIB_DIR} -lThapi

  THAPI_SYNC_DAEMON=fs THAPI_JOBID=0 timeout 40s $MPIRUN -n 2 $IPROF --trace-output toggle_traces --no-analysis -- ./thapi_toggle_mpi 0
  count_0=$(toggle_count_vpids)

  THAPI_SYNC_DAEMON=fs THAPI_JOBID=0 timeout 40s $MPIRUN -n 2 $IPROF --trace-output toggle_traces --no-analysis -- ./thapi_toggle_mpi 1
  count_1=$(toggle_count_vpids)

  [ "$count_0" -eq 2 ]
  [ "$count_1" -eq 1 ]
}
