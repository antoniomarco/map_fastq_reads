#!/bin/bash
# ============================================================
#  job_sam2bam.sh  (GridEngine job)
#  Converts a sample's SAM to a sorted, indexed BAM with
#  samtools, then deletes the SAM file.
#  Expects: SAMPLE, CONFIG (path to pipeline_config.sh)
#  Runs only after job_hisat2.sh for the same sample has
#  finished (enforced via qsub -hold_jid); additionally
#  verifies the SAM file actually exists and is non-empty.
# ============================================================
#$ -S /bin/bash
#$ -j y
#$ -cwd
#$ -N sam2bam

set -uo pipefail

source "$CONFIG"

LOG="$LOGS_DIR/${SAMPLE}.samtools.log"
SAM="$MAPPED_DIR/${SAMPLE}.sam"
BAM="$MAPPED_DIR/${SAMPLE}.sorted.bam"

echo "[$(date)] Checking SAM input for sample=$SAMPLE" | tee -a "$LOG"
if [ ! -s "$SAM" ]; then
    echo "[$(date)] ERROR: HISAT2 step did not produce a usable SAM file for $SAMPLE ($SAM). Not running samtools." \
        | tee -a "$LOG" >&2
    exit 1
fi

echo "[$(date)] Converting/sorting/indexing $SAMPLE" | tee -a "$LOG"
{
    samtools view -@ "$THREADS" -bS "$SAM" \
        | samtools sort -@ "$THREADS" -o "$BAM" - \
    && samtools index -@ "$THREADS" "$BAM"
} >> "$LOG" 2>&1
STATUS=$?

if [ $STATUS -ne 0 ] || [ ! -s "$BAM" ] || [ ! -s "${BAM}.bai" ]; then
    echo "[$(date)] ERROR: samtools sort/index failed for $SAMPLE (exit $STATUS). See $LOG" \
        | tee -a "$LOG" >&2
    exit 1
fi

rm -f "$SAM"
echo "[$(date)] BAM + index ready for $SAMPLE: $BAM. SAM removed." | tee -a "$LOG"
exit 0
