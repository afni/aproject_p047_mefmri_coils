#!/bin/tcsh

# FS: run freesurfer for surface estimation and anatomical parcellation
#
# Process a single subj. Run it from its partner run*.tcsh script.
# Run on a slurm/swarm system (like Biowulf) or on a desktop.
# ---------------------------------------------------------------------------

# ----------------------------- biowulf cmd ---------------------------------
# setup system

# use slurm? 1 = yes, 0 = no (def: use if available)
set use_slurm = $?SLURM_CLUSTER_NAME

# *** set relevant environment variables
setenv AFNI_COMPRESSOR GZIP           # zip BRIK dsets

if ( $use_slurm ) then
    # load modules: *** add any other necessary ones
    source /etc/profile.d/modules.csh
    module load afni freesurfer/7.4.1
    source $FREESURFER_HOME/SetUpFreeSurfer.csh

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

# ---------------------------- path setup -----------------------------------
# upper directories
set dir_inroot     = ${PWD:h}
set dir_log        = ${dir_inroot}/logs
set dir_basic      = ${dir_inroot}/data_00_basic
set dir_gtkyd      = ${dir_inroot}/data_02_gtkyd
set dir_deob       = ${dir_inroot}/data_05_deob_slice
set dir_fs         = ${dir_inroot}/data_12_fs

# subject directories
set sdir_basic     = ${dir_basic}/${subjpa}
set sdir_deob      = ${dir_deob}/${subjpa}
set sdir_func      = ${sdir_deob}/func            # input for proc
set sdir_anat      = ${sdir_deob}/anat
set sdir_fs        = ${dir_fs}/${subjpa}
set sdir_suma      = ${sdir_fs}/SUMA

set sdir_out       = ${sdir_fs}                 # *** set output directory
set lab_out        = ${sdir_out:t}

# supplementary directories and info
set dir_suppl      = ${dir_inroot}/supplements
set template       = MNI152_2009_template_SSW.nii.gz
# --------------------------------------------------------------------------

# ---------------------------- data setup ----------------------------------
# dataset inputs

# anat data (full path)
set dset_anat = `find ${sdir_anat} -name "${subjid}*T1w.nii*" | sort`

if ( ${#dset_anat} != 1 ) then
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

# don't use -parallel, bc that tends to be unstable
time recon-all                                                        \
    -all                                                              \
    -sd        .                                                      \
    -subjid    "${subjid}"                                            \
    -i         "${dset_anat}"                                         \
    |& tee log_fs_${subjid}.txt

if ( ${status} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# compress path (because of recon-all output dir naming): 
# move output from DIR/${subjid}/${ses}/${subjid}/* to DIR/${subjid}/${ses}/*
\mv    ${subjid}/* .
\rmdir ${subjid}

@SUMA_Make_Spec_FS                                                    \
    -fs_setup                                                         \
    -NIFTI                                                            \
    -sid       "${subjid}"                                            \
    -fspath    .

if ( ${status} ) then
    set ecode = 2
    goto COPY_AND_EXIT
endif

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

