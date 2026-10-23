#!/usr/bin/env bash
# Bounded random errors in three Euler angles (degrees) and x/y shifts (pixels).
# Uses SIMPLE text I/O, awk, and GNU coreutils; no Python or SIMPLE changes.
set -euo pipefail
export LC_ALL=C
if [[ $# -lt 1 || $# -gt 2 || ${1:-} == --help ]]; then
    echo "Usage: bash $0 INPUT.simple [SEED]"
    echo 'Uses $simple_exec when set, otherwise simple_exec on PATH.'
    echo 'Requires Bash, awk and GNU coreutils (od, dd, stat, cmp, mktemp).'
    echo 'Creates INPUT_err5deg_1px.simple, INPUT_err10deg_3px.simple,'
    echo 'INPUT_err15deg_5px.simple and INPUT_err20deg_7px.simple beside INPUT.simple.'
    echo 'Euler errors: uniform +/-angular maximum, truncated at the polar 0/180 limits.'
    echo 'Added x/y shifts: independent uniform 0..paired pixel maximum.'
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi
die() { echo "Pose perturbation failed: $*" >&2; exit 1; }
for tool in awk od dd stat cmp mktemp cp ln rm cat tail grep; do
    command -v "$tool" >/dev/null || die "Required tool is unavailable: $tool"
done
simple_executable=$(command -v "${simple_exec:-simple_exec}") || die 'Cannot find $simple_exec or simple_exec on PATH.'
simple_executable=$(cd -- "$(dirname -- "$simple_executable")" && pwd -P)/$(basename -- "$simple_executable")
[[ $1 == *.simple && -f $1 ]] || die 'Input must be an existing .simple project.'
source_dir=$(cd -- "$(dirname -- "$1")" && pwd -P)
source_project="$source_dir/$(basename -- "$1")"
base=${source_project%.simple}
seed=${2:-${SIMPLE_SEED:-$(($(date +%s) + RANDOM))}}
[[ $seed =~ ^[0-9]+$ && ${#seed} -le 18 ]] || die 'SEED must be a nonnegative integer with at most 18 digits.'
for case_bounds in 5:1 10:3 15:5 20:7; do
    maximum=${case_bounds%:*}
    shift_max=${case_bounds#*:}
    for target in "${base}_err${maximum}deg_${shift_max}px.simple" "${base}_err${maximum}deg_${shift_max}px.log"; do
        [[ ! -e $target && ! -L $target ]] || die "Refusing to overwrite: $target"
    done
done
work=$(mktemp -d "$source_dir/.pose-errors.XXXXXXXX")
logfile="$work/setup.log"
active_output=
cleanup() {
    local status=$?
    trap - EXIT
    if (( status != 0 )); then
        [[ ! -f $logfile ]] || { echo "Preparation log: $logfile" >&2; tail -80 "$logfile" >&2; }
        # Only delete a project successfully created by this invocation.
        [[ -z $active_output ]] || rm -f -- "$active_output"
    fi
    rm -rf -- "$work"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -- "$source_project" "$work/original.simple"
cp -- "$source_project" "$work/input.simple"

# Native binoris header: 20 segments, each five native int64 values:
# first,last,record_bytes,count,first_data_byte (1-based). Validate before dd.
layout() {
    local size
    size=$(stat -c %s -- "$1")
    [[ $size -ge 800 ]] || return 1
    od -An -v -t d8 -w40 -N800 -- "$1" | awk -v size="$size" '
        NF != 5 { bad=1; next }
        {
            if ($4 != 0) {
                if ($1 != 1 || $2 != $4 || $3 <= 0 || $4 < 0 || $5 <= 800 ||
                    $5-1+$3*$4 > size) bad=1
                start[NR]=$5-1; end[NR]=$5-1+$3*$4
            }
            if (NR==6) { offset=$5-1; width=$3; count=$4 }
        }
        END {
            for (a in start) for (b in start)
                if (a != b && start[a]<end[b] && start[b]<end[a]) bad=1
            if (NR!=20 || count<1 || width%4 || bad) exit 1
            printf "%.0f %.0f %.0f %.0f\n",offset,width,count,width*count
        }'
}
extract_payload() {
    local info offset width count length
    info=$(layout "$1") || die "Unsupported or invalid project layout: $1"
    read -r offset width count length <<<"$info"
    dd if="$1" of="$2" bs=1M iflag=skip_bytes,count_bytes skip="$offset" count="$length" status=none
    printf '%s\n' "$info"
}
original_layout=$(extract_payload "$work/original.simple" "$work/original.payload")
read -r original_offset original_width count length <<<"$original_layout"
run_simple() {
    local status=0
    printf '>>> ' >>"$logfile"
    printf '%q ' "$simple_executable" "$@" mkdir=no nthr=1 >>"$logfile"
    printf '\n' >>"$logfile"
    (cd -- "$work" && "$simple_executable" "$@" mkdir=no nthr=1) >"$work/command.log" 2>&1 || status=$?
    cat "$work/command.log" >>"$logfile"
    if (( status != 0 )) || grep -qE 'ERROR!|ERROR STOP|Fortran runtime error' "$work/command.log"; then
        die "SIMPLE command failed; see $logfile"
    fi
    if [[ $1 == prg=oriops ]]; then
        grep -q 'SIMPLE_oriops NORMAL STOP' "$work/command.log" || die "Incomplete oriops command; see $logfile"
    fi
}
encode() {
    local encoded_layout offset width encoded_count encoded_length
    rm -f -- "$work/encoded.simple"
    run_simple prg=oriops "oritab=$1" "outfile=$work/encoded.simple" oritype=ptcl3D "nptcls=$count"
    encoded_layout=$(extract_payload "$work/encoded.simple" "$work/encoded.payload")
    read -r offset width encoded_count encoded_length <<<"$encoded_layout"
    [[ $width == "$original_width" && $encoded_count == "$count" ]] || die 'Native particle record layout differs from the input.'
}
# SIMPLE may record CLI job history. Only pass the disposable input copy.
run_simple prg=oriops "oritab=$work/input.simple" "outfile=$work/original.txt" oritype=ptcl3D
encode "$work/original.txt"
cmp -s -- "$work/original.payload" "$work/encoded.payload" || die 'Native text round trip is lossy for this project; no output written.'
cp -- "$logfile" "$work/baseline.log"
printf 'Random seed: %s (Park-Miller generator; independent seed + maximum per arm).\n' "$seed"
for case_bounds in 5:1 10:3 15:5 20:7; do
    maximum=${case_bounds%:*}
    shift_max=${case_bounds#*:}
    output="${base}_err${maximum}deg_${shift_max}px.simple"
    logfile="${output%.simple}.log"
    (set -o noclobber; : >"$logfile") || die "Refusing to overwrite: $logfile"
    printf 'SIMPLE_SEED=%s\nANGLE_MAX_DEG=%s\nSHIFT_MAX_PX=%s\n' "$seed" "$maximum" "$shift_max" >>"$logfile"
    cat "$work/baseline.log" >>"$logfile"
    echo "Creating $output"
    # Explicit PRNG avoids awk rand()/srand() implementation differences.
    # Products stay below 2^53, so integer arithmetic is exact in awk doubles.
    awk -v seed="$seed" -v maximum="$maximum" -v shift_max="$shift_max" -v count="$count" '
        function uniform() { state=(16807*state)%2147483647; return (state-1)/2147483646 }
        function fail(message) { print message > "/dev/stderr"; bad=1; exit 1 }
        BEGIN {
            state=0
            for(i=1;i<=length(seed);i++) state=(state*10+substr(seed,i,1))%2147483646
            state=(state+maximum)%2147483646+1
        }
        {
            found=0
            for(i=1;i<=NF;i++) {
                split($i,pair,"="); key=pair[1]
                if(key !~ /^(e1|e2|e3|x|y)$/) continue
                if(pair[2] !~ /^[-+]?[0-9]+([.][0-9]*)?([eE][-+]?[0-9]+)?$/)
                    fail("Non-finite or invalid pose value")
                value=pair[2]+0; found++
                if(key=="x" || key=="y") value+=shift_max*uniform()
                else if(key=="e2") {
                    if(value<0 || value>180) fail("Polar angle must lie in [0,180]")
                    low=value-maximum; if(low<0) low=0
                    high=value+maximum; if(high>180) high=180
                    value=low+(high-low)*uniform()
                } else {
                    value=(value+maximum*(2*uniform()-1))%360
                    if(value<0) value+=360
                }
                $i=key "=" sprintf("%.9g",value)
            }
            if(found!=5) fail("Missing or duplicate pose variables")
            print
        }
        END { if(NR!=count || bad) exit 1 }
    ' "$work/original.txt" >"$work/changed.txt" || die 'Could not generate perturbed orientations.'
    encode "$work/changed.txt"
    run_simple prg=oriops "oritab=$work/encoded.simple" "outfile=$work/decoded.txt" oritype=ptcl3D
    # Check all native-decoded fields, including non-pose fields and row counts.
    awk -v maximum="$maximum" -v shift_max="$shift_max" -v count="$count" '
        function abs(x) { return x<0 ? -x : x }
        function fail(message) { print message > "/dev/stderr"; bad=1; exit 1 }
        FILENAME==ARGV[1] || FILENAME==ARGV[2] {
            which=(FILENAME==ARGV[1] ? 1 : 2)
            rows[which]++; fields[which,FNR]=NF
            for(i=1;i<=NF;i++) { split($i,p,"="); values[which,FNR,p[1]]=p[2] }
            next
        }
        {
            if(NF!=fields[1,FNR]) fail("Native field count changed")
            found=0
            for(i=1;i<=NF;i++) {
                split($i,p,"="); key=p[1]; value=p[2]
                if(!((1,FNR,key) in values)) fail("Native field names changed")
                old=values[1,FNR,key]; expected=values[2,FNR,key]
                if(key !~ /^(e1|e2|e3|x|y)$/) {
                    if(("v" value)!=("v" old)) fail("Non-pose field changed: " key)
                    continue
                }
                found++
                if(abs(value-expected)>0.0001) fail("Pose did not survive native import: " key)
                delta=value-old
                if(key=="e1" || key=="e3") { delta=(delta+180)%360; if(delta<0)delta+=360; delta-=180 }
                low=(key=="x" || key=="y") ? 0 : -maximum
                high=(key=="x" || key=="y") ? shift_max : maximum
                if(delta<low-0.0001 || delta>high+0.0001) fail("Pose exceeds bound: " key)
                if(key=="e2" && (value<0 || value>180)) fail("Polar angle outside [0,180]")
            }
            if(found!=5) fail("Missing pose fields")
        }
        END { if(rows[1]!=count || rows[2]!=count || FNR!=count || bad) exit 1 }
    ' "$work/original.txt" "$work/changed.txt" "$work/decoded.txt" || die 'Native orientation validation failed.'
    cp -- "$work/original.simple" "$work/candidate.simple"
    dd if="$work/encoded.payload" of="$work/candidate.simple" bs=1M oflag=seek_bytes seek="$original_offset" count="$length" iflag=count_bytes conv=notrunc status=none
    # A hard link publishes only a new path and refuses existing files/symlinks.
    ln -T -- "$work/candidate.simple" "$output" || die "Refusing to overwrite: $output"
    active_output=$output
    run_simple prg=update_project "projfile=$output"
    extract_payload "$output" "$work/final.payload" >/dev/null
    cmp -s -- "$work/encoded.payload" "$work/final.payload" || die 'Project identity update changed particle records.'
    active_output=
    rm -- "$work/candidate.simple"
    printf 'PASS: native pose round trip, bounds, count, and non-pose fields verified\n' >>"$logfile"
done
cmp -s -- "$source_project" "$work/original.simple" || die 'Input project changed during preparation.'
