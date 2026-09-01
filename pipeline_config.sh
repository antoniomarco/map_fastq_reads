#!/bin/bash
# ============================================================
#  pipeline_config.sh
#  Shared configuration for the trim/map RNA-seq pipeline.
#  Sourced by run_pipeline_local.sh AND by the GridEngine
#  scripts under sge/. Edit the values below as needed.
# ============================================================

# ---------------------------------------------------------------
# ---- USER-EDITABLE SETTINGS ------------------------------------
# ---------------------------------------------------------------

# Path prefix to the HISAT2 index (what you would pass to `hisat2 -x`)
# e.g. /data/genomes/hg38/hisat2_index/hg38  (do NOT include .1.ht2 etc.)
HISAT2_INDEX="/path/to/genome/hisat2_index/genome_prefix"

# Directory containing the raw input fastq(.gz) files
RAW_DIR="raw_data"

# Output directories (created automatically if missing)
TRIMMED_DIR="trimmed"
MAPPED_DIR="mapped"
LOGS_DIR="logs"

# Threads used by trim_galore / hisat2 / samtools
THREADS=8

# Extra options passed verbatim to trim_galore / hisat2 (leave empty if none)
TRIMGALORE_EXTRA_OPTS=""
HISAT2_EXTRA_OPTS=""

# Recognised fastq suffixes, most specific first
FASTQ_SUFFIXES=(".fastq.gz" ".fq.gz" ".fastq" ".fq")

# ---- GridEngine-only settings (used by sge/submit_pipeline.sh) --
SGE_QUEUE=""              # e.g. "all.q"   (leave empty for cluster default)
SGE_PE="smp"              # parallel environment name for multi-threaded jobs
SGE_EXTRA_OPTS=""         # extra qsub options, e.g. "-l h_vmem=4G"

# ---------------------------------------------------------------
# ---- END USER-EDITABLE SETTINGS --------------------------------
# ---------------------------------------------------------------

# Resolve to absolute paths so jobs submitted from any directory,
# or run on remote compute nodes, still find everything correctly.
RAW_DIR="$(cd "$RAW_DIR" 2>/dev/null && pwd || echo "$RAW_DIR")"
mkdir -p "$TRIMMED_DIR" "$MAPPED_DIR" "$LOGS_DIR"
TRIMMED_DIR="$(cd "$TRIMMED_DIR" && pwd)"
MAPPED_DIR="$(cd "$MAPPED_DIR" && pwd)"
LOGS_DIR="$(cd "$LOGS_DIR" && pwd)"
