#!/bin/bash
# ============================================================
#  job_hisat2.sh  (GridEngine job)
#  Aligns the trimmed reads of a single sample with HISAT2.
#  Expects: SAMPLE, TYPE (PE|SE), READ1, READ2 (or "NA"),
#           CONFIG (path to pipeline_config.sh)
#  Runs only after job_trim_galore.sh for the same sample has
#  finished (enforced via qsub -hold_jid by the submit driver);
#  it additionally verifies the trimmed files actually exist,
#  since -hold_jid alone does not guarantee the predecessor
#  succeeded.
# ============================================================
#$ -S /bin/bash
#$ -j y
#$ -cwd
#$ -N align

set -uo pipefail

source "$CONFIG"

LOG="$LOGS_DIR/${SAMPLE}.hisat2.log"
SUMMARY="$LOGS_DIR/${SAMPLE}.hisat2_summary.log"

r1_base=$(basename "$READ1")
for suf in "${FASTQ_SUFFIXES[@]}"; do r1_base="${r1_base%$suf}"; done

if [[ "$TYPE" == "PE" ]]; then
    r2_base=$(basename "$READ2")
    for suf in "${FASTQ_SUFFIXES[@]}"; do r2_base="${r2_base%$suf}"; done
    T_R1="$TRIMMED_DIR/${r1_base}_val_1.fq.gz"
    T_R2="$TRIMMED_DIR/${r2_base}_val_2.fq.gz"
else
    T_R1="$TRIMMED_DIR/${r1_base}_trimmed.fq.gz"
fi

echo "[$(date)] Checking trimmed input for sample=$SAMPLE" | tee -a "$LOG"
if [ ! -s "$T_R1" ] || { [[ "$TYPE" == "PE" ]] && [ ! -s "$T_R2" ]; }; then
    echo "[$(date)] ERROR: Trim Galore step did not produce expected input for $SAMPLE ($T_R1). Not running HISAT2." \
        | tee -a "$LOG" >&2
    exit 1
fi

echo "[$(date)] Starting HISAT2 for sample=$SAMPLE type=$TYPE" | tee -a "$LOG"
SAM="$MAPPED_DIR/${SAMPLE}.sam"

if [[ "$TYPE" == "PE" ]]; then
    hisat2 -x "$HISAT2_INDEX" -1 "$T_R1" -2 "$T_R2" \
        -p "$THREADS" $HISAT2_EXTRA_OPTS \
        --summary-file "$SUMMARY" -S "$SAM" >> "$LOG" 2>&1
else
    hisat2 -x "$HISAT2_INDEX" -U "$T_R1" \
        -p "$THREADS" $HISAT2_EXTRA_OPTS \
        --summary-file "$SUMMARY" -S "$SAM" >> "$LOG" 2>&1
fi
STATUS=$?

if [ $STATUS -ne 0 ] || [ ! -s "$SAM" ]; then
    echo "[$(date)] ERROR: HISAT2 failed for $SAMPLE (exit $STATUS) or produced no SAM. See $LOG / $SUMMARY" \
        | tee -a "$LOG" >&2
    exit 1
fi

echo "[$(date)] HISAT2 finished OK for $SAMPLE. Summary: $SUMMARY" | tee -a "$LOG"
exit 0
