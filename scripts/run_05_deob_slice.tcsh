#!/bin/tcsh

# DEOBandSLICE: add slice timing info to any FMRI dset that has it
#               (don't need to deob any anat here)

# Process one or more subjects via corresponding do_*.tcsh script.
# This script loops over pre-made list of IDs, which can be made
# either directly by the user or, for example, via run_00*.tcsh.

# This script runs on a slurm/swarm system (like Biowulf) or on a desktop.
# To execute:  
#     tcsh RUN_SCRIPT_NAME

# ---------------------------------------------------------------------------

# use slurm? 1 = yes, 0 = no, def: use if available
set use_slurm = $?SLURM_CLUSTER_NAME

# --------------------------------------------------------------------------

# specify script to execute
set cmd           = 05_deob_slice

# upper directories
set dir_scr       = $PWD
set dir_inroot    = ..
set dir_log       = ${dir_inroot}/logs
set dir_swarm     = ${dir_inroot}/swarms
set dir_suppl     = ${dir_inroot}/supplements
set dir_basic     = ${dir_inroot}/data_00_basic

# input files 
set file_run      = ${dir_suppl}/list_data_00_run.txt

# names for logging and swarming/running
set cdir_log      = ${dir_log}/logs_${cmd}
set scr_swarm     = ${dir_swarm}/swarm_${cmd}.txt
set scr_cmd       = ${dir_scr}/do_${cmd}.tcsh

# --------------------------------------------------------------------------
# create log and swarm dirs

\mkdir -p ${cdir_log}
\mkdir -p ${dir_swarm}

# clear away older swarm script 
if ( -e ${scr_swarm} ) then
    \rm ${scr_swarm}
endif

# --------------------------------------------------------------------------
# read list subj to process and setup swarm command

set nin = `cat ${file_run} | wc -l`
echo "++ INFO: Found ${nin} lines in file: ${file_run}"

# for printing, below
set ndig = `echo ${nin} | wc -m`
@   ndig+= 1

# read each line of the file (ignoring empty or whitespace-only lines)
set ncount = 0

foreach ii ( `seq 1 1 ${nin}` )
    # extract values to list, path and ID versions
    set subjli = `sed -n ${ii}p ${file_run}`
    if ( ${#subjli} ) then
        @ ncount+= 1

        set subjid = `python -c "print('_'.join(('${subjli}').split()))"`
        set subjpa = `python -c "print('/'.join(('${subjli}').split()))"`
        printf "   %-${ndig}s %s\n" "[$ii]" "${subjpa}"

        # log file name 
        set log = ${cdir_log}/log_${cmd}_${subjid}.txt

        # add cmd to the swarm script (verbosely, but don't use '-e')
        # and log terminal text.
        echo "tcsh -xf ${scr_cmd} ${subjli} |& tee ${log}" >> ${scr_swarm}
    endif
end

if ( ! ${ncount} ) then
    echo "* ERROR: exiting, no data to run"
    exit 1
endif

# -------------------------------------------------------------------------
# run swarm command

cd ${dir_scr}

echo "++ And start swarming: ${scr_swarm}"

if ( $use_slurm ) then
    # swarm, if we are on a slurm-job system

    # ** NB: these parameter settings depend very much on the job
    # ** being done, the size of the data involved, and the
    # ** software being used. Each task will get its own setup like
    # ** this, which might have to be testd over time.

    swarm                                                          \
        -f ${scr_swarm}                                            \
        --partition=norm,quick                                     \
        --threads-per-process=1                                    \
        --gb-per-process=4                                         \
        --time=00:10:00                                            \
        ##--gres=lscratch:10                                         \
        --logdir=${cdir_log}                                       \
        --job-name=job_${cmd}                                      \
        --merge-output                                             \
        --usecsh
else
    # ... otherwise, simply execute the processing script
    tcsh ${scr_swarm}
endif

