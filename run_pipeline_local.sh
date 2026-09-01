#!/bin/bash
# ============================================================
#  run_pipeline_local.sh
#  Straight command-line version of the trim/map pipeline.
#
#  Steps per sample:
#    1. Trim Galore (also runs FastQC)      -> trimmed/
#    2. HISAT2 alignment                    -> mapped/*.sam
#    3. samtools sort SAM -> sorted BAM + index -> mapped/
#    4. Delete the SAM file
#    5. All logs (Trim Galore, FastQC, HISAT2, samtools) -> logs/
#
#  Usage:
#     ./run_pipeline_local.sh
#  (edit pipeline_config.sh first to set HISAT2_INDEX and RAW_DIR)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pipeline_config.sh"
source "$SCRIPT_DIR/lib_detect_samples.sh"

MANIFEST="$LOGS_DIR/sample_manifest.tsv"

echo "== Step 0: detecting fastq files in '$RAW_DIR' =="
if ! generate_manifest "$RAW_DIR" "$MANIFEST"; then
    echo "FATAL: could not build sample manifest. Aborting." >&2
    exit 1
fi
echo "Manifest written to: $MANIFEST"
cat "$MANIFEST"
echo

FAILED_SAMPLES=()

run_trim_galore() {
    local sample="$1" type="$2" r1="$3" r2="$4"
    local log="$LOGS_DIR/${sample}.trimgalore.log"

    echo "  [trim_galore] $sample ($type)"
    if [[ "$type" == "PE" ]]; then
        trim_galore --paired --fastqc --cores "$THREADS" \
            --output_dir "$TRIMMED_DIR" $TRIMGALORE_EXTRA_OPTS \
            "$r1" "$r2" > "$log" 2>&1
    else
        trim_galore --fastqc --cores "$THREADS" \
            --output_dir "$TRIMMED_DIR" $TRIMGALORE_EXTRA_OPTS \
            "$r1" > "$log" 2>&1
    fi
    return $?
}

# Work out the file names Trim Galore produces so downstream steps
# know what to feed into HISAT2.
trimmed_paths() {
    local sample="$1" type="$2" r1="$3" r2="$4"
    local r1_base r2_base
    r1_base=$(basename "$r1")
    for suf in "${FASTQ_SUFFIXES[@]}"; do
        r1_base="${r1_base%"$suf"}"
    done
    if [[ "$type" == "PE" ]]; then
        r2_base=$(basename "$r2")
        for suf in "${FASTQ_SUFFIXES[@]}"; do
            r2_base="${r2_base%"$suf"}"
        done
        echo "$TRIMMED_DIR/${r1_base}_val_1.fq.gz" "$TRIMMED_DIR/${r2_base}_val_2.fq.gz"
    else
        echo "$TRIMMED_DIR/${r1_base}_trimmed.fq.gz" ""
    fi
}

run_hisat2() {
    local sample="$1" type="$2" t_r1="$3" t_r2="$4"
    local sam="$MAPPED_DIR/${sample}.sam"
    local summary="$LOGS_DIR/${sample}.hisat2_summary.log"
    local log="$LOGS_DIR/${sample}.hisat2.log"

    echo "  [hisat2] $sample ($type)"
    if [[ "$type" == "PE" ]]; then
        hisat2 -x "$HISAT2_INDEX" -1 "$t_r1" -2 "$t_r2" \
            -p "$THREADS" $HISAT2_EXTRA_OPTS \
            --summary-file "$summary" -S "$sam" > "$log" 2>&1
    else
        hisat2 -x "$HISAT2_INDEX" -U "$t_r1" \
            -p "$THREADS" $HISAT2_EXTRA_OPTS \
            --summary-file "$summary" -S "$sam" > "$log" 2>&1
    fi
    return $?
}

run_sam_to_bam() {
    local sample="$1"
    local sam="$MAPPED_DIR/${sample}.sam"
    local bam="$MAPPED_DIR/${sample}.sorted.bam"
    local log="$LOGS_DIR/${sample}.samtools.log"

    echo "  [samtools] $sample"
    {
        samtools view -@ "$THREADS" -bS "$sam" \
            | samtools sort -@ "$THREADS" -o "$bam" - \
        && samtools index -@ "$THREADS" "$bam"
    } > "$log" 2>&1
    return $?
}

echo "== Processing samples =="
while IFS=$'\t' read -r sample type r1 r2; do
    [ -z "$sample" ] && continue
    echo "-- Sample: $sample ($type) --"

    if ! run_trim_galore "$sample" "$type" "$r1" "$r2"; then
        echo "  ERROR: Trim Galore failed for $sample. See $LOGS_DIR/${sample}.trimgalore.log" >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    read -r t_r1 t_r2 <<< "$(trimmed_paths "$sample" "$type" "$r1" "$r2")"
    if [ ! -s "$t_r1" ] || { [[ "$type" == "PE" ]] && [ ! -s "$t_r2" ]; }; then
        echo "  ERROR: expected trimmed output not found for $sample ($t_r1 / $t_r2)." >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    if ! run_hisat2 "$sample" "$type" "$t_r1" "$t_r2"; then
        echo "  ERROR: HISAT2 failed for $sample. See $LOGS_DIR/${sample}.hisat2.log" >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    if [ ! -s "$MAPPED_DIR/${sample}.sam" ]; then
        echo "  ERROR: SAM file missing/empty for $sample after HISAT2." >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    if ! run_sam_to_bam "$sample"; then
        echo "  ERROR: SAM->BAM conversion/indexing failed for $sample. See $LOGS_DIR/${sample}.samtools.log" >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    if [ ! -s "$MAPPED_DIR/${sample}.sorted.bam.bai" ]; then
        echo "  ERROR: BAM index missing for $sample." >&2
        FAILED_SAMPLES+=("$sample")
        continue
    fi

    rm -f "$MAPPED_DIR/${sample}.sam"
    echo "  OK: $sample complete."
done < "$MANIFEST"

echo
if [ ${#FAILED_SAMPLES[@]} -eq 0 ]; then
    echo "All samples completed successfully."
    exit 0
else
    echo "Pipeline finished with errors in ${#FAILED_SAMPLES[@]} sample(s): ${FAILED_SAMPLES[*]}" >&2
    exit 1
fi
