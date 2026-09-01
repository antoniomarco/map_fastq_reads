#!/bin/bash
# ============================================================
#  job_trim_galore.sh  (GridEngine job)
#  Runs Trim Galore (+ FastQC) for a single sample.
#  Expects these environment variables to be set via `qsub -v`:
#     SAMPLE, TYPE (PE|SE), READ1, READ2 (or "NA"),
#     CONFIG (path to pipeline_config.sh)
# ============================================================
#$ -S /bin/bash
#$ -j y
#$ -cwd
#$ -N trim
# (queue/PE/threads and -o/-e are set dynamically by submit_pipeline.sh)

set -uo pipefail

source "$CONFIG"

LOG="$LOGS_DIR/${SAMPLE}.trimgalore.log"
echo "[$(date)] Starting Trim Galore for sample=$SAMPLE type=$TYPE" | tee -a "$LOG"

if [[ "$TYPE" == "PE" ]]; then
    trim_galore --paired --fastqc --cores "$THREADS" \
        --output_dir "$TRIMMED_DIR" $TRIMGALORE_EXTRA_OPTS \
        "$READ1" "$READ2" >> "$LOG" 2>&1
else
    trim_galore --fastqc --cores "$THREADS" \
        --output_dir "$TRIMMED_DIR" $TRIMGALORE_EXTRA_OPTS \
        "$READ1" >> "$LOG" 2>&1
fi
STATUS=$?

if [ $STATUS -ne 0 ]; then
    echo "[$(date)] ERROR: Trim Galore failed for $SAMPLE (exit $STATUS). See $LOG" | tee -a "$LOG" >&2
    exit 1
fi

# Verify expected trimmed output exists before declaring success,
# so the next job (HISAT2) can rely on this step having worked.
r1_base=$(basename "$READ1")
for suf in "${FASTQ_SUFFIXES[@]}"; do r1_base="${r1_base%$suf}"; done

if [[ "$TYPE" == "PE" ]]; then
    r2_base=$(basename "$READ2")
    for suf in "${FASTQ_SUFFIXES[@]}"; do r2_base="${r2_base%$suf}"; done
    OUT1="$TRIMMED_DIR/${r1_base}_val_1.fq.gz"
    OUT2="$TRIMMED_DIR/${r2_base}_val_2.fq.gz"
    if [ ! -s "$OUT1" ] || [ ! -s "$OUT2" ]; then
        echo "[$(date)] ERROR: expected trimmed files not found ($OUT1 / $OUT2)" | tee -a "$LOG" >&2
        exit 1
    fi
else
    OUT1="$TRIMMED_DIR/${r1_base}_trimmed.fq.gz"
    if [ ! -s "$OUT1" ]; then
        echo "[$(date)] ERROR: expected trimmed file not found ($OUT1)" | tee -a "$LOG" >&2
        exit 1
    fi
fi

echo "[$(date)] Trim Galore finished OK for $SAMPLE" | tee -a "$LOG"
exit 0
