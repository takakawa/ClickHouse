#!/bin/bash
# shellcheck disable=SC2086

set -eux
set -o pipefail
trap "exit" INT TERM
# The watchdog is in the separate process group, so we have to kill it separately
# if the script terminates earlier.
trap 'kill $(jobs -pr) ${watchdog_pid:-} ||:' EXIT

stage=${stage:-}
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "$script_dir"
repo_dir=ch
BINARY_TO_DOWNLOAD=${BINARY_TO_DOWNLOAD:="clang-11_debug_none_bundled_unsplitted_disable_False_binary"}

function clone
{
    # The download() function is dependent on CI binaries anyway, so we can take
    # the repo from the CI as well. For local runs, start directly from the "fuzz"
    # stage.
    rm -rf ch ||:
    mkdir ch
    cd ch
    wget -nv -nd -c "https://clickhouse-test-reports.s3.yandex.net/$PR_TO_TEST/$SHA_TO_TEST/repo/clickhouse_no_subs.tar.gz"
    tar -xvf clickhouse_no_subs.tar.gz
    tree ||:
    ls -lath ||:
}

function download
{
    wget -nv -nd -c "https://clickhouse-builds.s3.yandex.net/$PR_TO_TEST/$SHA_TO_TEST/clickhouse_build_check/$BINARY_TO_DOWNLOAD/clickhouse" &
    wget -nv -nd -c "https://clickhouse-test-reports.s3.yandex.net/$PR_TO_TEST/$SHA_TO_TEST/repo/ci-changed-files.txt" &
    wait

    chmod +x clickhouse
    ln -s ./clickhouse ./clickhouse-server
    ln -s ./clickhouse ./clickhouse-client

    # clickhouse-server is in the current dir
    export PATH="$PWD:$PATH"
}

function configure
{
    rm -rf db ||:
    mkdir db ||:
    cp -av --dereference "$repo_dir"/programs/server/config* db
    cp -av --dereference "$repo_dir"/programs/server/user* db
    # TODO figure out which ones are needed
    cp -av --dereference "$repo_dir"/tests/config/config.d/listen.xml db/config.d
    cp -av --dereference "$script_dir"/query-fuzzer-tweaks-users.xml db/users.d
}

function watchdog
{
    sleep 3600

    echo "Fuzzing run has timed out"
    killall clickhouse-client ||:
    for _ in {1..10}
    do
        if ! pgrep -f clickhouse-client
        then
            break
        fi
        sleep 1
    done

    killall -9 clickhouse-client ||:
}

function fuzz
{
    # Obtain the list of newly added tests. They will be fuzzed in more extreme way than other tests.
    # Don't overwrite the NEW_TESTS_OPT so that it can be set from the environment.
    NEW_TESTS="$(grep -P 'tests/queries/0_stateless/.*\.sql' ci-changed-files.txt | sed -r -e 's!^!ch/!' | sort -R)"
    if [[ -n "$NEW_TESTS" ]]
    then
        NEW_TESTS_OPT="${NEW_TESTS_OPT:---interleave-queries-file ${NEW_TESTS}}"
    else
        NEW_TESTS_OPT="${NEW_TESTS_OPT:-}"
    fi

    clickhouse-server --config-file db/config.xml -- --path db 2>&1 | tail -100000 > server.log &

    server_pid=$!
    kill -0 $server_pid
    while ! clickhouse-client --query "select 1" && kill -0 $server_pid ; do echo . ; sleep 1 ; done
    clickhouse-client --query "select 1"
    kill -0 $server_pid
    echo Server started

    echo "
handle all noprint
handle SIGSEGV stop print
handle SIGBUS stop print
continue
thread apply all backtrace
continue
" > script.gdb

    gdb -batch -command script.gdb -p "$(pidof clickhouse-server)" &

    fuzzer_exit_code=0
    # SC2012: Use find instead of ls to better handle non-alphanumeric filenames. They are all alphanumeric.
    # SC2046: Quote this to prevent word splitting. Actually I need word splitting.
    # shellcheck disable=SC2012,SC2046
    clickhouse-client --query-fuzzer-runs=1000 --queries-file $(ls -1 ch/tests/queries/0_stateless/*.sql | sort -R) $NEW_TESTS_OPT \
        > >(tail -n 100000 > fuzzer.log) \
        2>&1 \
        || fuzzer_exit_code=$?

    echo "Fuzzer exit code is $fuzzer_exit_code"

    clickhouse-client --query "select elapsed, query from system.processes" ||:
    killall clickhouse-server ||:
    for _ in {1..10}
    do
        if ! pgrep -f clickhouse-server
        then
            break
        fi
        sleep 1
    done
    killall -9 clickhouse-server ||:
}

case "$stage" in
"")
    ;&  # Did you know? This is "fallthrough" in bash. https://stackoverflow.com/questions/12010686/case-statement-fallthrough
"clone")
    time clone
    if [ -v FUZZ_LOCAL_SCRIPT ]
    then
        # just fall through
        echo Using the testing script from docker container
        :
    else
        # Run the testing script from the repository
        echo Using the testing script from the repository
        export stage=download
        time ch/docker/test/fuzzer/run-fuzzer.sh
        # Keep the error code
        exit $?
    fi
    ;&
"download")
    time download
    ;&
"configure")
    time configure
    ;&
"fuzz")
    # Start a watchdog that should kill the fuzzer on timeout.
    # The shell won't kill the child sleep when we kill it, so we have to put it
    # into a separate process group so that we can kill them all.
    set -m
    watchdog &
    watchdog_pid=$!
    set +m
    # Check that the watchdog has started
    kill -0 $watchdog_pid

    fuzzer_exit_code=0
    time fuzz || fuzzer_exit_code=$?
    kill -- -$watchdog_pid ||:

    # Debug
    date
    sleep 10
    jobs
    pstree -aspgT

    # Make files with status and description we'll show for this check on Github
    task_exit_code=$fuzzer_exit_code
    if [ "$fuzzer_exit_code" == 143 ]
    then
        # SIGTERM -- the fuzzer was killed by timeout, which means a normal run.
        echo "success" > status.txt
        echo "OK" > description.txt
        task_exit_code=0
    elif [ "$fuzzer_exit_code" == 210 ]
    then
        # Lost connection to the server. This probably means that the server died
        # with abort.
        echo "failure" > status.txt
        if ! grep -ao "Received signal.*\|Logical error.*\|Assertion.*failed\|Failed assertion.*\|.*runtime error: .*\|.*is located.*\|SUMMARY: MemorySanitizer:.*\|SUMMARY: ThreadSanitizer:.*" server.log > description.txt
        then
            echo "Lost connection to server. See the logs." > description.txt
        fi
    else
        # Something different -- maybe the fuzzer itself died? Don't grep the
        # server log in this case, because we will find a message about normal
        # server termination (Received signal 15), which is confusing.
        echo "failure" > status.txt
        echo "Fuzzer failed ($fuzzer_exit_code). See the logs." > description.txt
    fi
    ;&
"report")
cat > report.html <<EOF ||:
<!DOCTYPE html>
<html lang="en">
<link rel="preload" as="font" href="https://yastatic.net/adv-www/_/sUYVCPUAQE7ExrvMS7FoISoO83s.woff2" type="font/woff2" crossorigin="anonymous"/>
  <style>
@font-face {
    font-family:'Yandex Sans Display Web';
    src:url(https://yastatic.net/adv-www/_/H63jN0veW07XQUIA2317lr9UIm8.eot);
    src:url(https://yastatic.net/adv-www/_/H63jN0veW07XQUIA2317lr9UIm8.eot?#iefix) format('embedded-opentype'),
            url(https://yastatic.net/adv-www/_/sUYVCPUAQE7ExrvMS7FoISoO83s.woff2) format('woff2'),
            url(https://yastatic.net/adv-www/_/v2Sve_obH3rKm6rKrtSQpf-eB7U.woff) format('woff'),
            url(https://yastatic.net/adv-www/_/PzD8hWLMunow5i3RfJ6WQJAL7aI.ttf) format('truetype'),
            url(https://yastatic.net/adv-www/_/lF_KG5g4tpQNlYIgA0e77fBSZ5s.svg#YandexSansDisplayWeb-Regular) format('svg');
    font-weight:400;
    font-style:normal;
    font-stretch:normal
}

body { font-family: "Yandex Sans Display Web", Arial, sans-serif; background: #EEE; }
h1 { margin-left: 10px; }
th, td { border: 0; padding: 5px 10px 5px 10px; text-align: left; vertical-align: top; line-height: 1.5; background-color: #FFF;
td { white-space: pre; font-family: Monospace, Courier New; }
border: 0; box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.05), 0 8px 25px -5px rgba(0, 0, 0, 0.1); }
a { color: #06F; text-decoration: none; }
a:hover, a:active { color: #F40; text-decoration: underline; }
table { border: 0; }
.main { margin-left: 10%; }
p.links a { padding: 5px; margin: 3px; background: #FFF; line-height: 2; white-space: nowrap; box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.05), 0 8px 25px -5px rgba(0, 0, 0, 0.1); }
th { cursor: pointer; }

  </style>
  <title>AST Fuzzer for PR #${PR_TO_TEST} @ ${SHA_TO_TEST}</title>
</head>
<body>
<div class="main">

<h1>AST Fuzzer for PR #${PR_TO_TEST} @ ${SHA_TO_TEST}</h1>
<p class="links">
<a href="fuzzer.log">fuzzer.log</a>
<a href="server.log">server.log</a>
<a href="main.log">main.log</a>
</p>
<table>
<tr><th>Test name</th><th>Test status</th><th>Description</th></tr>
<tr><td>AST Fuzzer</td><td>$(cat status.txt)</td><td>$(cat description.txt)</td></tr>
</table>
</body>
</html>

EOF
    ;&
esac

exit $task_exit_code
