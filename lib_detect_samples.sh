#!/bin/bash
# ============================================================
#  lib_detect_samples.sh
#  Scans a directory for fastq files and builds a "manifest"
#  TSV describing each sample and whether it is paired-end (PE)
#  or single-end (SE).
#
#  Manifest columns (tab-separated, no header):
#    sample_name  PE|SE  read1_path  read2_path(or NA)
#
#  Recognises common naming conventions:
#    sample_R1.fastq.gz / sample_R2.fastq.gz
#    sample_R1_001.fastq.gz / sample_R2_001.fastq.gz
#    sample_1.fq.gz / sample_2.fq.gz
#    sample.1.fastq / sample.2.fastq
#    sample.fastq.gz                (treated as single-end)
# ============================================================

generate_manifest() {
    local raw_dir="$1"
    local manifest="$2"

    : > "$manifest"

    declare -A r1_of
    declare -A r2_of
    declare -A is_paired

    shopt -s nullglob
    local all_files=()
    for suf in "${FASTQ_SUFFIXES[@]}"; do
        for f in "$raw_dir"/*"$suf"; do
            all_files+=("$f")
        done
    done
    shopt -u nullglob

    if [ ${#all_files[@]} -eq 0 ]; then
        echo "ERROR: No fastq files found in '$raw_dir' (looked for: ${FASTQ_SUFFIXES[*]})" >&2
        return 1
    fi

    for f in "${all_files[@]}"; do
        local base stripped suf sample mate matched
        base=$(basename "$f")

        # Strip the recognised fastq suffix
        stripped="$base"
        matched=0
        for suf in "${FASTQ_SUFFIXES[@]}"; do
            if [[ "$stripped" == *"$suf" ]]; then
                stripped="${stripped%"$suf"}"
                matched=1
                break
            fi
        done
        [ "$matched" -eq 1 ] || continue

        sample=""
        mate=""

        if [[ "$stripped" =~ ^(.*)_R([12])(_[0-9]+)?$ ]]; then
            # e.g. sample_R1, sample_R1_001
            sample="${BASH_REMATCH[1]}"
            mate="${BASH_REMATCH[2]}"
        elif [[ "$stripped" =~ ^(.*)[._]([12])$ ]]; then
            # e.g. sample_1 / sample.1
            sample="${BASH_REMATCH[1]}"
            mate="${BASH_REMATCH[2]}"
        else
            # No mate marker found -> single-end
            sample="$stripped"
            mate=""
        fi

        if [[ -z "$mate" ]]; then
            r1_of["$sample"]="$f"
            is_paired["$sample"]=0
        elif [[ "$mate" == "1" ]]; then
            r1_of["$sample"]="$f"
            is_paired["$sample"]=${is_paired["$sample"]:-1}
        else
            r2_of["$sample"]="$f"
            is_paired["$sample"]=${is_paired["$sample"]:-1}
        fi
    done

    for sample in "${!r1_of[@]}"; do
        if [[ "${is_paired[$sample]}" == "1" ]]; then
            if [[ -z "${r2_of[$sample]:-}" ]]; then
                echo "WARNING: mate R2 not found for sample '$sample' (R1: ${r1_of[$sample]}). Treating as single-end." >&2
                printf "%s\tSE\t%s\tNA\n" "$sample" "${r1_of[$sample]}" >> "$manifest"
            else
                printf "%s\tPE\t%s\t%s\n" "$sample" "${r1_of[$sample]}" "${r2_of[$sample]}" >> "$manifest"
            fi
        else
            printf "%s\tSE\t%s\tNA\n" "$sample" "${r1_of[$sample]}" >> "$manifest"
        fi
    done

    if [ ! -s "$manifest" ]; then
        echo "ERROR: manifest generation produced no entries." >&2
        return 1
    fi

    sort -o "$manifest" "$manifest"
    return 0
}
