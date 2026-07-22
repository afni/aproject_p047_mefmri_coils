#!/bin/tcsh

# DEOBandSLICE: add slice timing info to any FMRI dset that has it
#               (don't need to deob any anat here)

# Process a single subj. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.

# ----------------------------- biowulf cmd ---------------------------------
# setup system

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = $?SLURM_CLUSTER_NAME

# *** set relevant environment variables
setenv AFNI_COMPRESSOR GZIP           # zip BRIK dsets

if ( $use_slurm ) then
    # load modules: *** add any other necessary ones
    module load afni 

    # set N_threads for OpenMP
    setenv OMP_NUM_THREADS $SLURM_CPUS_ON_NODE
endif
# ---------------------------------------------------------------------------

# ============================= session info ================================
# set initial exit code; we don't exit at fail, to copy partial results back
set ecode   = 0
set usetemp = 0

# check available N_threads and report what is being used
set nthr_avail = `afni_system_check.py -disp_num_cpu`
set nthr_using = `afni_check_omp`

echo "++ INFO: Using ${nthr_using} of available ${nthr_avail} threads"
# ===========================================================================

# =========================== read subject ID ===============================
# general level version

# set subject component list (can include: site, subj, ses)
set subjli = ( ${argv[1-]} )
echo "++ Have ${#subjli} vals to make labels and paths: ${subjli}"

set aaa = `python adjunct_parse_subjli.py ${subjli}`
if ( ${aaa[1]} ) then
    set ecode = ${aaa[1]}
    goto COPY_AND_EXIT
endif

# subject ID and data path
set subjid = "${aaa[2]}"
set subjpa = "${aaa[3]}"
# ===========================================================================

# ---------------------------------------------------------------------------
# top level definitions (paths)
# ---------------------------------------------------------------------------

# upper directories
set dir_inroot     = ${PWD:h}                     # one dir above scripts/
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_00_basic
set dir_gtkyd      = ${dir_inroot}/data_02_gtkyd
set dir_deob       = ${dir_inroot}/data_05_deob_slice

# subject directories
set sdir_basic     = ${dir_basic}/${subjpa}
set sdir_func      = ${sdir_basic}/func
set sdir_fmap      = ${sdir_basic}/fmap
set sdir_anat      = ${sdir_basic}/anat
set sdir_deob      = ${dir_deob}/${subjpa}

set sdir_out       = ${sdir_deob}                 # *** set output directory
set lab_out        = ${sdir_out:t}

# supplementary directories and info
set dir_suppl      = ${dir_inroot}/supplements
set template       = ${dir_suppl}/MNI152_2009_template_SSW.nii.gz

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

# EPI data
cd ${sdir_func}
set taskname      = rest
set label         = task-${taskname}
set dset_epi      = ( ${subjid}*${label}*_bold.nii* )
cd -

if ( ! ${#dset_epi} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# anat data
cd ${sdir_anat}
set dset_anat = ( ${subjid}*T1w.nii* )
cd -

if ( ! ${#dset_anat} ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif

# --------------------------------------------------------------------------

# ============================= biowulf cmd ================================
if ( $use_slurm ) then
    # try to use /lscratch for speed; store "real" output dir for later copy
    if ( -d /lscratch/$SLURM_JOBID ) then
        set usetemp  = 1
        set sdir_BW  = ${sdir_out}
        set sdir_out = /lscratch/$SLURM_JOBID/${subjid}

        # prep for group permission reset
        \mkdir -p ${sdir_BW}
        set grp_own  = `\ls -ld ${sdir_BW} | awk '{print $4}'`
    else
        set usetemp  = 0
    endif
endif
# ===========================================================================

# --------------------------- run programs ----------------------------------

# make output directory and jump to it
\mkdir -p ${sdir_out}

cd ${sdir_out}

# ----- EPI dset: make outdir, copy with json and add any slice timing info
\mkdir -p func

foreach dset ( ${dset_epi} )
    echo "++ Proc: ${sdir_func}/${dset}"

    # dset name without NIFTI ext pieces
    set dset_name = `basename ${dset} .gz`
    set dset_name = `basename ${dset_name} .nii`

    # get json file name
    set json = ${dset_name}.json

    # copy dset and JSON
    \cp ${sdir_func}/${dset} func/${dset}
    \cp ${sdir_func}/${json} func/${json}

    if ( ${status} ) then
        set ecode = 4
        goto COPY_AND_EXIT
    endif

    # check for slice timing in JSON, and add to dset header if present
    set check_st = `abids_json_info.py                    \
                        -json   func/${json}              \
                        -field  SliceTiming`
    if ( "${check_st}" != "None" ) then
        echo "++ Attach slice timing for: ${dset}"
        abids_tool.py                                     \
            -add_slice_times                              \
            -input            func/${dset}

        if ( ${status} ) then
            set ecode = 4
            goto COPY_AND_EXIT
        endif
    else
        echo "+* No SliceTiming to copy: func/${json}"
    endif
end

# ----- anat dset: make outdir, copy, and remove any obliquity
\mkdir -p anat

foreach dset ( ${dset_anat} )
    echo "++ Proc: ${sdir_anat}/${dset}"

    # dset name without NIFTI ext pieces
    set dset_name = `basename ${dset} .gz`
    set dset_name = `basename ${dset_name} .nii`

    # get json file name
    set json = ${dset_name}.json

    # remove any obliquity nicely (or copy)
    adjunct_deob_around_origin                       \
        -input   ${sdir_anat}/${dset}                \
        -prefix  anat/${dset} 

    if ( ${status} ) then
        set ecode = 6
        goto COPY_AND_EXIT
    endif

    # json: copy if present
    if ( -f ${sdir_anat}/${json} ) then
        \cp ${sdir_anat}/${json} anat/${json}
    else
        echo "+* No JSON to copy: ${sdir_anat}/${json}"
    endif
end

echo "++ FINISHED ${lab_out}"

# ---------------------------------------------------------------------------

COPY_AND_EXIT:

# ============================= biowulf cmd ================================
if ( $use_slurm ) then
    # if using /lscratch, copy back to "real" location
    if( ${usetemp} && -d ${sdir_out} ) then
        echo "++ Used /lscratch"
        echo "++ Copy from: ${sdir_out}"
        echo "          to: ${sdir_BW}"
        \cp -pr   ${sdir_out}/* ${sdir_BW}/.

        # reset group permission
        chgrp -R ${grp_own} ${sdir_BW}
    endif
endif
# ===========================================================================

# =============================== finish ====================================
if ( ${ecode} ) then
    echo "++ BAD FINISH: ${lab_out} (ecode = ${ecode})"
else
    echo "++ GOOD FINISH: ${lab_out}"
endif

exit ${ecode}
# ===========================================================================

