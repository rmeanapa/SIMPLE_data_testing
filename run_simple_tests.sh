#!/usr/bin/env bash

# Discover and run the test programs advertised by simple_test_exec test=list.
# Each test runs in its own directory so generated files cannot affect later tests.

set -u
set -o pipefail

usage() {
    cat <<'EOF'
Usage: ~/run_simple_tests.sh [options] [-- extra-test-arguments...]

Options:
  --exe PATH          simple_test_exec to run
                      (default: $SIMPLE_PATH/bin/simple_test_exec)
  --output-dir DIR    Directory for logs and per-test working directories
                      (default: simple-test-results/<timestamp>-<pid>)
  --timeout SECONDS   Per-test timeout; 0 disables it (default: 300)
  --match REGEX       Run only test names matching this extended regular expression
  --exclude REGEX     Skip test names matching this extended regular expression
                      (default: coarrays, openacc, mini_stream,
                      and simulated_workflow)
  --no-fixtures       Do not generate synthetic inputs for data-dependent tests
  --list-only         Print the selected test names without running them
  -h, --help          Show this help

Arguments after -- are passed to every selected test. The global `nthr`
argument is intentionally unsupported because not every test accepts it.

The runner continues after failures and exits nonzero when any test fails or
times out. Some advertised programs require input data or are long-running
services; their logs will show the parameters or environment they need.

Tests are discovered from `simple_test_exec test=list` on every invocation.
Newly advertised tests are selected automatically unless they match --exclude.
EOF
}

die() {
    echo "error: $*" >&2
    exit 2
}

test_exe=
output_dir=
timeout_seconds=300
match_regex='.*'
exclude_regex='^(coarrays|openacc|mini_stream|simulated_workflow|single_workflow)$'
generate_fixtures=1
list_only=0
extra_args=()

while (($# > 0)); do
    case "$1" in
        --exe)
            (($# >= 2)) || die "--exe requires a path"
            test_exe=$2
            shift 2
            ;;
        --output-dir)
            (($# >= 2)) || die "--output-dir requires a directory"
            output_dir=$2
            shift 2
            ;;
        --timeout)
            (($# >= 2)) || die "--timeout requires a number of seconds"
            timeout_seconds=$2
            shift 2
            ;;
        --match)
            (($# >= 2)) || die "--match requires a regular expression"
            match_regex=$2
            shift 2
            ;;
        --exclude)
            (($# >= 2)) || die "--exclude requires a regular expression"
            exclude_regex=$2
            shift 2
            ;;
        --no-fixtures)
            generate_fixtures=0
            shift
            ;;
        --list-only)
            list_only=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while (($# > 0)); do
                case "$1" in
                    nthr|nthr=*)
                        die "nthr cannot be passed globally; let each test use its own thread setting"
                        ;;
                esac
                extra_args+=("$1")
                shift
            done
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

case "$timeout_seconds" in
    ''|*[!0-9]*)
        die "--timeout must be a non-negative integer"
        ;;
esac

[[ -n "${SIMPLE_PATH:-}" ]] || die "SIMPLE_PATH is not set"

if [[ -z "$test_exe" ]]; then
    test_exe="${SIMPLE_PATH}/bin/simple_test_exec"
elif [[ "$test_exe" != */* ]]; then
    resolved_exe=$(command -v "$test_exe" 2>/dev/null) ||
        die "executable not found in PATH: $test_exe"
    test_exe=$resolved_exe
fi

[[ -x "$test_exe" ]] || die "not an executable file: $test_exe"
test_exe=$(cd "$(dirname "$test_exe")" && pwd)/$(basename "$test_exe")
test_bin_dir=$(dirname "$test_exe")
PATH="${SIMPLE_PATH}/bin:${test_bin_dir}:${PATH}"
export PATH
if [[ -z "${SIMPLE_QSYS:-}" ]]; then
    SIMPLE_QSYS=local
    export SIMPLE_QSYS
fi
simple_exe="${SIMPLE_PATH}/bin/simple_exec"
if ((generate_fixtures)) && [[ ! -x "$simple_exe" ]]; then
    die "fixture generation requires simple_exec next to simple_test_exec: $simple_exe"
fi

list_output=$("$test_exe" test=list 2>&1)
list_status=$?
if ((list_status != 0)); then
    echo "$list_output" >&2
    die "test discovery failed with exit status $list_status"
fi

tests=()
while IFS= read -r test_name; do
    [[ "$test_name" =~ $match_regex ]] || continue
    if [[ -n "$exclude_regex" && "$test_name" =~ $exclude_regex ]]; then
        continue
    fi
    tests+=("$test_name")
done < <(
    echo "$list_output" |
        awk '
            BEGIN { esc = sprintf("%c", 27) }
            {
                line = $0
                gsub(esc "\\[[0-9;]*[[:alpha:]]", "", line)
                sub(/\r$/, "", line)
                if (line == "" || line ~ /:$/) next
                if (line ~ /^[[:alnum:]_.-]+$/ && !seen[line]++) print line
            }
        '
)

((${#tests[@]} > 0)) || die "no tests matched the requested filters"

if ((list_only)); then
    for test_name in "${tests[@]}"; do
        echo "$test_name"
    done
    exit 0
fi

if [[ -z "$output_dir" ]]; then
    output_dir="${PWD}/simple-test-results/$(date '+%Y%m%d-%H%M%S')-$$"
elif [[ "$output_dir" != /* ]]; then
    output_dir="${PWD}/${output_dir}"
fi

if [[ -e "$output_dir" ]]; then
    die "output directory already exists: $output_dir"
fi

mkdir -p "${output_dir}/logs" "${output_dir}/work" ||
    die "could not create output directory: $output_dir"

echo "$list_output" >"${output_dir}/test-list.raw"
summary_file="${output_dir}/summary.tsv"
printf 'test\tstatus\texit_code\tduration_seconds\tlog\n' >"$summary_file"

timeout_tool=
timeout_exit_code=
if ((timeout_seconds > 0)); then
    if command -v timeout >/dev/null 2>&1; then
        timeout_tool=$(command -v timeout)
        timeout_exit_code=124
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_tool=$(command -v gtimeout)
        timeout_exit_code=124
    elif command -v perl >/dev/null 2>&1; then
        timeout_tool=perl
        timeout_exit_code=142
    else
        die "no timeout implementation found; install timeout or perl, or use --timeout 0"
    fi
fi

run_test() {
    if ((timeout_seconds == 0)); then
        "$@"
    elif [[ "$timeout_tool" == "perl" ]]; then
        perl -e '
            my $seconds = shift @ARGV;
            alarm $seconds;
            exec @ARGV or die "cannot execute $ARGV[0]: $!\n";
        ' "$timeout_seconds" "$@"
    else
        "$timeout_tool" --signal=TERM --kill-after=10 "$timeout_seconds" "$@"
    fi
}

generate_noise_stack() {
    output_name=$1
    box_size=$2
    particle_count=$3
    "$simple_exe" prg=simulate_noise "box=${box_size}" \
        "nptcls=${particle_count}" "outstk=${output_name}" mkdir=no
}

generate_noise_volume() {
    output_name=$1
    box_size=$2
    sampling_distance=$3
    "$simple_exe" prg=noisevol "box=${box_size}" \
        "smpd=${sampling_distance}" nstates=1
    mv noisevol_state01.mrc "$output_name"
    rm -f noisevol_state01_even.mrc noisevol_state01_odd.mrc
}

generate_rec3d_backends_fixture() {
    generate_noise_volume rec3d_truth.mrc 32 1.0
    "$simple_exe" prg=simulate_particles vol1=rec3d_truth.mrc \
        smpd=1.0 nptcls=128 snr=1000000 pgrp=c1 mskdiam=24 nthr=1 \
        ctf=no even=yes mkdir=no outstk=rec3d_particles.mrc \
        outfile=rec3d_oris.txt
    "$simple_exe" prg=new_project projname=rec3d_fixture qsys_name=local
    (
        cd rec3d_fixture || exit 2
        "$simple_exe" prg=import_particles \
            projfile=rec3d_fixture.simple stk=../rec3d_particles.mrc \
            oritab=../rec3d_oris.txt smpd=1.0 kv=300 cs=2.7 fraca=0.1 \
            ctf=no mkdir=no
    )
}

prepare_test_fixtures() {
    test_name=$1
    case "$test_name" in
        reproject)
            generate_noise_volume 6VXX.mrc 192 1.3
            ;;
        gencorrs_fft)
            generate_noise_stack fixture_particles.mrcs 256 2
            ;;
        eval_polarftcc)
            generate_noise_volume fixture_volume.mrc 192 1.3
            ;;
        mrc2jpeg)
            generate_noise_stack fixture_images.mrcs 64 2
            printf '%s\n' fixture_images.mrcs >fixture_images.txt
            ;;
        mrc_validate)
            generate_noise_volume fixture_volume.mrc 64 1.3
            ;;
        stack_io)
            generate_noise_stack cavgs_iter030_ranked.mrc 256 4
            ;;
        star_export)
            "$test_exe" test=inside_write
            cp original_proj.simple test.simple
            ;;
        nano_mask)
            generate_noise_stack selected.spi 512 4
            ;;
        ptcl_center)
            generate_noise_volume fixture_volume.mrc 192 1.0
            ;;
        opt_lp)
            generate_noise_stack fixture_particles.mrcs 192 2
            ;;
        eo_diff)
            "$simple_exe" prg=noisevol box=300 smpd=1.2156 nstates=1
            mv noisevol_state01.mrc recvol_state01.mrc
            mv noisevol_state01_even.mrc recvol_state01_even.mrc
            mv noisevol_state01_odd.mrc recvol_state01_odd.mrc
            ;;
        rec3D_backends)
            generate_rec3d_backends_fixture
            ;;
        ptcls_ppca_subproject_distr)
            generate_noise_stack fixture_particle.mrc 64 1
            printf '%s\n' fixture_particle.mrc fixture_particle.mrc \
                fixture_particle.mrc fixture_particle.mrc \
                >fixture_particles.txt
            ;;
        pcg_frac_update)
            generate_noise_volume fixture_volume.mrc 32 1.5
            "$simple_exe" prg=simulate_particles vol1=fixture_volume.mrc \
                smpd=1.5 nptcls=12 snr=0.1 ctf=yes pgrp=c1 \
                mskdiam=30 nthr=1 outstk=fixture_particles.mrcs \
                outfile=fixture_oris.txt even=yes
            "$simple_exe" prg=new_project projname=pcg_fixture
            "$simple_exe" prg=import_particles \
                projfile=pcg_fixture/pcg_fixture.simple \
                stk=fixture_particles.mrcs oritab=fixture_oris.txt \
                smpd=1.5 kv=300 cs=2.7 fraca=0.1 ctf=yes mkdir=no
            ;;
    esac
}

set_test_specific_args() {
    test_name=$1
    test_work_dir=$2
    test_specific_args=()
    case "$test_name" in
        ptcls_ppca_subproject_distr)
            test_specific_args=(filetab=fixture_particles.txt smpd=1.3 nparts=2)
            ;;
        gencorrs_fft)
            test_specific_args=(stk=fixture_particles.mrcs mskdiam=160 smpd=1.3)
            ;;
        eval_polarftcc)
            test_specific_args=(vol1=fixture_volume.mrc mskdiam=160 lp=10 smpd=1.3)
            ;;
        mrc2jpeg)
            test_specific_args=(filetab=fixture_images.txt smpd=1.3)
            ;;
        mrc_validate)
            test_specific_args=(vol=fixture_volume.mrc smpd=1.3)
            ;;
        nano_mask)
            test_specific_args=(stk=selected.spi smpd=0.358 mskdiam=100)
            ;;
        ptcl_center)
            test_specific_args=(smpd=1.0 nthr=1 vol1=fixture_volume.mrc mskdiam=160 lp=3)
            ;;
        opt_lp)
            test_specific_args=(smpd=1.0 nthr=1 stk=fixture_particles.mrcs mskdiam=160)
            ;;
        rec3D_backends)
            test_specific_args=(projfile=rec3d_fixture/rec3d_fixture.simple \
                pgrp=c1 mskdiam=24 nthr=1 objfun=cc ml_reg=no \
                maxits_pcg=8 mkdir=no)
            ;;
        atoms_stats|detect_atoms|simulate_nanoparticle|single_workflow)
            test_specific_args=(smpd=0.5 element=Au)
            ;;
        pcg_frac_update)
            test_specific_args=(projfile=pcg_fixture/pcg_fixture.simple \
                pgrp=c1 mskdiam=30 nthr=1 objfun=cc ml_reg=no)
            ;;
    esac
}

run_socket_pair() {
    client_probe_log=socket-client-probe.log
    "$test_exe" test=socket_server "$@" &
    server_pid=$!
    sleep 1

    if ! kill -0 "$server_pid" 2>/dev/null; then
        wait "$server_pid"
        return 1
    fi

    run_test "$test_exe" test=socket_client "$@" \
        >"$client_probe_log" 2>&1
    client_status=$?
    cat "$client_probe_log"

    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true

    if ((client_status != 0)); then
        return "$client_status"
    fi
    if grep -Eqi 'failed to connect|operation not permitted|error stop' \
        "$client_probe_log"; then
        return 1
    fi
    grep -q 'Sent message' "$client_probe_log"
}

test_completed_normally() {
    awk '
        /^===== TEST EXECUTION =====$/ {
            in_test = 1
            next
        }
        in_test && /NORMAL STOP/ {
            found = 1
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "$1"
}

passed=0
failed=0
timed_out=0
failed_tests=()
total=${#tests[@]}
index=0

echo "Executable: $test_exe"
echo "Tests:      $total"
echo "Results:    $output_dir"
if ((timeout_seconds == 0)); then
    echo "Timeout:    disabled"
else
    echo "Timeout:    ${timeout_seconds}s per test"
fi
if ((generate_fixtures)); then
    echo "Fixtures:   generated for supported data-dependent tests"
else
    echo "Fixtures:   disabled"
fi
echo

for test_name in "${tests[@]}"; do
    index=$((index + 1))
    test_work_dir="${output_dir}/work/${test_name}"
    test_log="${output_dir}/logs/${test_name}.log"
    mkdir -p "$test_work_dir" || die "could not create work directory for $test_name"
    : >"$test_log"

    printf '[%d/%d] %-36s ' "$index" "$total" "$test_name"
    started=$(date +%s)

    setup_status=0
    if ((generate_fixtures)); then
        {
            echo "===== FIXTURE SETUP ====="
            (
                cd "$test_work_dir" || exit 2
                prepare_test_fixtures "$test_name"
            )
        } >>"$test_log" 2>&1
        setup_status=$?
    fi

    set_test_specific_args "$test_name" "$test_work_dir"
    common_args=()
    if ((${#test_specific_args[@]} > 0)); then
        common_args+=("${test_specific_args[@]}")
    fi
    if ((${#extra_args[@]} > 0)); then
        common_args+=("${extra_args[@]}")
    fi

    test_status=0
    if ((setup_status == 0)); then
        {
            echo "===== TEST EXECUTION ====="
            (
                cd "$test_work_dir" || exit 2
                if [[ "$test_name" == "socket_client" ||
                      "$test_name" == "socket_server" ]]; then
                    if ((${#common_args[@]} > 0)); then
                        run_socket_pair "${common_args[@]}"
                    else
                        run_socket_pair
                    fi
                elif ((${#common_args[@]} > 0)); then
                    run_test "$test_exe" "test=${test_name}" "${common_args[@]}"
                else
                    run_test "$test_exe" "test=${test_name}"
                fi
            )
        } >>"$test_log" 2>&1
        test_status=$?
    else
        test_status=$setup_status
    fi
    finished=$(date +%s)
    duration=$((finished - started))

    if ((setup_status != 0)); then
        status=SETUP_FAIL
        failed=$((failed + 1))
        failed_tests+=("${test_name} (fixture setup exit ${setup_status})")
    elif [[ -n "$timeout_exit_code" && "$test_status" -eq "$timeout_exit_code" ]]; then
        status=TIMEOUT
        timed_out=$((timed_out + 1))
        failed_tests+=("${test_name} (timeout)")
    elif ((test_status == 0)) && test_completed_normally "$test_log"; then
        status=PASS
        passed=$((passed + 1))
    else
        status=FAIL
        failed=$((failed + 1))
        if ((test_status == 0)); then
            failed_tests+=("${test_name} (no normal-stop marker)")
        else
            failed_tests+=("${test_name} (exit ${test_status})")
        fi
    fi

    printf '%s (%ss)\n' "$status" "$duration"
    printf '%s\t%s\t%d\t%d\t%s\n' \
        "$test_name" "$status" "$test_status" "$duration" "$test_log" \
        >>"$summary_file"
done

echo
echo "Summary: $passed passed, $failed failed, $timed_out timed out, $total total"
echo "Details: $summary_file"

if ((failed + timed_out > 0)); then
    echo "Unsuccessful tests:"
    for test_name in "${failed_tests[@]}"; do
        echo "  - $test_name"
    done
    exit 1
fi

exit 0
