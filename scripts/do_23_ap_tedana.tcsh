#!/bin/tcsh

# AP_TEDANA: run AP processing with tedana for ME-FMRI data

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
    module load afni tedana

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
set dir_ssw        = ${dir_inroot}/data_13_ssw
set dir_ap         = ${dir_inroot}/data_23_ap_tedana

# subject directories
set sdir_basic     = ${dir_basic}/${subjpa}
set sdir_deob      = ${dir_deob}/${subjpa}
set sdir_func      = ${sdir_deob}/func            # input for proc
set sdir_anat      = ${sdir_deob}/anat
set sdir_ssw       = ${dir_ssw}/${subjpa}
set sdir_ap        = ${dir_ap}/${subjpa}


set sdir_out       = ${sdir_ap}                   # *** set output directory
set lab_out        = ${sdir_out:t}

# supplementary directories and info
set dir_suppl      = ${dir_inroot}/supplements
set template       = ${dir_suppl}/MNI152_2009_template_SSW.nii.gz

# --------------------------------------------------------------------------
# data and control variables
# --------------------------------------------------------------------------

# dataset inputs

# EPI data (full path); only 1 run here
cd ${sdir_func}
set taskname    = rest
set label       = task-${taskname}
set dset_epi    = `find ${sdir_func} -name "${subjid}*${label}*_bold.nii*" \
                      | sort`
set json_epi    = `find ${sdir_func} -name "${subjid}*${label}*_bold.json" \
                        | sort`
# ... and get all echo times (in order)
set times_me    = `abids_json_info.py -json ${json_epi} -field EchoTime`

if ( ! ${#dset_epi} ) then
    set ecode = 1
    goto COPY_AND_EXIT
endif

# anat data (full path)
set dset_anat = `find ${sdir_anat} -name "${subjid}*T1w.nii*" \
                      | sort`

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

# create command script
set run_script = ap.cmd.${subjid}

cat << EOF >! ${run_script}

# Comments on processing, ME-FMRI data
#
# + input EPI dsets have 3.0 mm isotropic voxels, determining final size
# + for blur for this voxelwise analysis of ME EPI, blur just slightly above
#   input voxel dim
# + input EPI have pre-steady still, so remove a couple time points at start
# + use tedana's MEICA in a way to provide 3dD regressors, where "good" was
#   already projected from "bad", using m_tedana_OC_tedort

afni_proc.py                                                                  \
    -subj_id                   ${subjid}                                      \
    -dsets_me_run              ${dset_epi}                                    \
    -echo_times                ${times_me}                                    \
    -copy_anat                 ${sdir_ssw}/anatSS.${subjid}.nii               \
    -anat_has_skull            no                                             \
    -anat_follower          anat_w_skull anat ${sdir_ssw}/anatU.${subjid}.nii \
    -blocks                    tshift align tlrc volreg mask combine          \
                               blur scale regress                             \
    -radial_correlate_blocks   tcat volreg regress                            \
    -tcat_remove_first_trs     2                                              \
    -tshift_interp             -wsinc9                                        \
    -align_unifize_epi         local                                          \
    -align_opts_aea            -cost lpc+ZZ                                   \
                               -giant_move                                    \
                               -check_flip                                    \
    -tlrc_base                 ${template}                                    \
    -tlrc_NL_warp                                                             \
    -tlrc_NL_warped_dsets      ${sdir_ssw}/anatQQ.${subjid}.nii*              \
                               ${sdir_ssw}/anatQQ.${subjid}.aff12.1D          \
                               ${sdir_ssw}/anatQQ.${subjid}_WARP.nii*         \
    -volreg_align_to           MIN_OUTLIER                                    \
    -volreg_align_e2a                                                         \
    -volreg_tlrc_warp                                                         \
    -volreg_warp_dxyz          2.75                                           \
    -volreg_warp_final_interp  wsinc5                                         \
    -volreg_compute_tsnr       yes                                            \
    -mask_epi_anat             yes                                            \
    -combine_method            m_tedana_OC_tedort                             \
    -blur_size                 3.3                                            \
    -regress_motion_per_run                                                   \
    -regress_censor_motion     0.2                                            \
    -regress_censor_outliers   0.05                                           \
    -regress_apply_mot_types   demean deriv                                   \
    -regress_est_blur_epits                                                   \
    -regress_est_blur_errts                                                   \
    -html_review_style         pythonic

EOF

if ( ${status} ) then
    set ecode = 3
    goto COPY_AND_EXIT
endif


# execute AP command to make processing script
tcsh -xef ${run_script} |& tee output.ap.cmd.${subjid}

if ( ${status} ) then
    set ecode = 4
    goto COPY_AND_EXIT
endif


# execute the proc script, saving text info
time tcsh -xef proc.${subjid} |& tee output.proc.${subjid}

if ( ${status} ) then
    set ecode = 5
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

