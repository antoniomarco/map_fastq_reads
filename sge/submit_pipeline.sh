#!/bin/bash
# ============================================================
#  submit_pipeline.sh
#  GridEngine (qsub) version of the trim/map pipeline.
#
#  Run from the head/login node:
#     ./sge/submit_pipeline.sh
#
#  For every sample this submits 3 chained jobs:
#     trim_<sample>  ->  align_<sample>  ->  bam_<sample>
#  using `qsub -hold_jid` so each stage only *starts* after the
#  previous one has finished. Because GridEngine's -hold_jid does
#  not by itself guarantee the predecessor succeeded, each job
#  script (job_trim_galore.sh / job_hisat2.sh / job_sam2bam.sh)
#  independently checks that its required input files actually
#  exist before doing any work, and exits with an error (visible
#  in logs/ and in qacct/qstat) if not - so failures propagate
#  instead of silently continuing.
# ============================================================
set -uo pipefail

SGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SGE_DIR/.." && pwd)"
CONFIG="$ROOT_DIR/pipeline_config.sh"

source "$CONFIG"
source "$ROOT_DIR/lib_detect_samples.sh"

MANIFEST="$LOGS_DIR/sample_manifest.tsv"

echo "== Step 0: detecting fastq files in '$RAW_DIR' =="
if ! generate_manifest "$RAW_DIR" "$MANIFEST"; then
    echo "FATAL: could not build sample manifest. Aborting submission." >&2
    exit 1
fi
echo "Manifest written to: $MANIFEST"
cat "$MANIFEST"
echo

# Common qsub options (queue / parallel env / threads / extra opts)
COMMON_OPTS=(-cwd -j y)
[ -n "$SGE_QUEUE" ] && COMMON_OPTS+=(-q "$SGE_QUEUE")
[ -n "$SGE_PE" ] && COMMON_OPTS+=(-pe "$SGE_PE" "$THREADS")
if [ -n "$SGE_EXTRA_OPTS" ]; then
    # shellcheck disable=SC2206
    COMMON_OPTS+=($SGE_EXTRA_OPTS)
fi

SUBMITTED=0
SKIPPED=0

while IFS=$'\t' read -r sample type r1 r2; do
    [ -z "$sample" ] && continue
    echo "-- Submitting jobs for sample: $sample ($type) --"

    common_vars="SAMPLE=$sample,TYPE=$type,READ1=$r1,READ2=$r2,CONFIG=$CONFIG"

    # 1) Trim Galore + FastQC
    trim_out=$(qsub "${COMMON_OPTS[@]}" \
        -N "trim_${sample}" \
        -o "$LOGS_DIR/${sample}.trim.qsub.log" \
        -v "$common_vars" \
        "$SGE_DIR/jobs/job_trim_galore.sh")
    trim_jid=$(echo "$trim_out" | grep -oE '[0-9]+' | head -1)
    if [ -z "$trim_jid" ]; then
        echo "  ERROR: failed to submit Trim Galore job for $sample (qsub said: $trim_out)" >&2
        SKIPPED=$((SKIPPED+1))
        continue
    fi
    echo "  Submitted trim_${sample} as job $trim_jid"

    # 2) HISAT2 alignment - only starts once trim job has finished
    align_out=$(qsub "${COMMON_OPTS[@]}" \
        -N "align_${sample}" \
        -o "$LOGS_DIR/${sample}.align.qsub.log" \
        -hold_jid "$trim_jid" \
        -v "$common_vars" \
        "$SGE_DIR/jobs/job_hisat2.sh")
    align_jid=$(echo "$align_out" | grep -oE '[0-9]+' | head -1)
    if [ -z "$align_jid" ]; then
        echo "  ERROR: failed to submit HISAT2 job for $sample (qsub said: $align_out)" >&2
        SKIPPED=$((SKIPPED+1))
        continue
    fi
    echo "  Submitted align_${sample} as job $align_jid (holds on $trim_jid)"

    # 3) SAM -> sorted/indexed BAM, then delete SAM - only starts once
    #    the alignment job has finished
    bam_out=$(qsub "${COMMON_OPTS[@]}" \
        -N "bam_${sample}" \
        -o "$LOGS_DIR/${sample}.bam.qsub.log" \
        -hold_jid "$align_jid" \
        -v "SAMPLE=$sample,CONFIG=$CONFIG" \
        "$SGE_DIR/jobs/job_sam2bam.sh")
    bam_jid=$(echo "$bam_out" | grep -oE '[0-9]+' | head -1)
    if [ -z "$bam_jid" ]; then
        echo "  ERROR: failed to submit samtools job for $sample (qsub said: $bam_out)" >&2
        SKIPPED=$((SKIPPED+1))
        continue
    fi
    echo "  Submitted bam_${sample} as job $bam_jid (holds on $align_jid)"

    SUBMITTED=$((SUBMITTED+1))
done < "$MANIFEST"

echo
echo "Submission complete: $SUBMITTED sample(s) submitted, $SKIPPED sample(s) skipped due to submission errors."
echo "Track progress with: qstat -u \$USER"
echo "Per-sample logs (Trim Galore/FastQC, HISAT2, samtools) are in: $LOGS_DIR"
echo "qsub stdout/stderr for each stage: $LOGS_DIR/<sample>.<stage>.qsub.log"

[ "$SKIPPED" -eq 0 ]
