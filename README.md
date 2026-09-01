# Fastq trim + HISAT2 mapping pipeline

## Layout

```
pipeline_config.sh        <- EDIT THIS: reference index path, dirs, threads, etc.
lib_detect_samples.sh     <- shared library: finds fastq files, detects PE/SE
run_pipeline_local.sh     <- run everything directly on the command line
sge/
  submit_pipeline.sh      <- run everything via GridEngine (qsub), with job dependencies
  jobs/
    job_trim_galore.sh    <- SGE job: Trim Galore + FastQC
    job_hisat2.sh         <- SGE job: HISAT2 alignment
    job_sam2bam.sh         <- SGE job: samtools sort/index + delete SAM
```

## 1. Configure

Edit `pipeline_config.sh`:
- `HISAT2_INDEX` — path prefix to your HISAT2 index (required, no default).
- `RAW_DIR` — folder with your raw fastq/fq(.gz) files.
- `THREADS`, `SGE_QUEUE`, `SGE_PE`, `SGE_EXTRA_OPTS` — adjust to your cluster.

Requires `trim_galore`, `fastqc`, `hisat2`, and `samtools` on `$PATH`
(on a cluster, load these via `module load ...` before running, or add
that to the top of the job scripts / your shell profile).

## 2. Sample detection

Both versions call `generate_manifest()` from `lib_detect_samples.sh`,
which scans `RAW_DIR` for files ending in `.fastq`, `.fq`, `.fastq.gz`,
`.fq.gz` and groups mates using common naming patterns
(`_R1/_R2`, `_1/_2`, `.1/.2`, with or without an `_001` suffix).
Anything without a recognised mate marker is treated as single-end.
The resulting manifest is written to `logs/sample_manifest.tsv` and is
printed to the screen for review.

## 3a. Run locally

```bash
./run_pipeline_local.sh
```

Runs Trim Galore → HISAT2 → samtools sort/index → SAM cleanup for each
sample in sequence, checking the exit status and expected output files
after every step. If a step fails for a sample, that sample is skipped
and reported at the end; other samples still run. Exit code is 0 only
if every sample completed successfully.

## 3b. Run on a GridEngine cluster

```bash
./sge/submit_pipeline.sh
```

For each sample this submits three chained jobs:

```
trim_<sample>  --(-hold_jid)-->  align_<sample>  --(-hold_jid)-->  bam_<sample>
```

`-hold_jid` only delays the *start* of the next job until the previous
one finishes — it does not know whether that job succeeded. To make
failures propagate properly, each job script independently checks that
the expected input from the previous step actually exists before doing
any work, and exits with an error otherwise. So if Trim Galore fails,
the alignment job will start, immediately detect the missing trimmed
files, log a clear error, and exit non-zero without wasting compute —
and likewise for the samtools step if HISAT2 failed.

Track jobs with `qstat -u $USER`. Per-stage GridEngine stdout/stderr go
to `logs/<sample>.<stage>.qsub.log`; the pipeline's own logs (Trim
Galore, FastQC, HISAT2 summary, samtools) go to `logs/<sample>.*.log`.

## Outputs

- `trimmed/` — trimmed fastq files + FastQC reports (from Trim Galore)
- `mapped/`  — `<sample>.sorted.bam` + `<sample>.sorted.bam.bai` (SAM files are deleted after conversion)
- `logs/`    — sample manifest, Trim Galore/FastQC logs, HISAT2 logs + alignment summaries, samtools logs, and (SGE only) qsub stdout/stderr
