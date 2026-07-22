#!/bin/tcsh

# This is a helper script to make a list of subject IDs to process.
# This might also include session and/or site IDs.

# To execute:  
#     tcsh RUN_SCRIPT_NAME

# ---------------------------------------------------------------------------

# get the timestamp of execution
set thedate = `date +%Y_%m_%d_%H_%M_%S`

# the script being run
set prog = $0

# --------------------------------------------------------------------------
# define dir and file names

# upper directories
set dir_scr       = $PWD
set dir_inroot    = ${PWD:h}
set dir_basic     = ${dir_inroot}/data_00_basic
set dir_suppl     = ${dir_inroot}/supplements

# output files
set file_run      = ${dir_suppl}/list_data_00_run.txt
set file_skip     = ${dir_suppl}/list_data_00_skip.txt
set file_empty    = ${dir_suppl}/list_data_00_empty.txt

# temp files
set ftmp_run      = ${dir_suppl}/__tmp_list_data_00_run_${thedate}.txt
set ftmp_skip     = ${dir_suppl}/__tmp_list_data_00_skip_${thedate}.txt
set ftmp_empty    = ${dir_suppl}/__tmp_list_data_00_empty_${thedate}.txt

# --------------------------------------------------------------------------

# create log and swarm dirs
\mkdir -p ${dir_suppl}

# start empty temp file
printf "" > ${ftmp_run}
printf "" > ${ftmp_skip}
printf "" > ${ftmp_empty}

# --------------------------------------------------------------------------
# main work: search directory hierarchy to make proc list

# ----- top level of dirs
cd ${dir_basic}
set all_dir = `find . -mindepth 1 -maxdepth 1 -type d -name "*" \
                    | cut -b3- | sort`
cd -

cat <<EOF

++ Proc command:  ${prog}
++ Found ${#all_dir} top dirs

EOF

set ncheck = 0
set nempty = 0

foreach dir ( ${all_dir} )
    cd ${dir_basic}/${dir}
    echo "++ Check: ${PWD}"

    # find all func dirs
    set all_func = `find . -type d -name "func" | cut -b3- | sort`
    set nfunc = ${#all_func}

    if ( ! ${nfunc} ) then
        @ nempty+= 1
        echo "+* EMPTY dir (no func)"
        echo "${dir} ${dir_basic}/${dir}"    >> ${ftmp_empty}
    endif

    # loop over each to find data we want
    foreach nn ( `seq 1 1 ${nfunc}` )
        @ ncheck+= 1
        set func = "${all_func[$nn]}"

        # the key components, "subj" path and list of elements
        set subjpa = `dirname "${func}"`
        if ( "${subjpa}" == "." ) then
            # in this case, nothing to add to path
            set subjli = ( "${dir}" )
        else
            set subjli = ( "${dir}" `echo "${subjpa}" | tr '/' ' '` )
        endif
        set nlayer = ${#subjli}
        
        # make sure layer count stays constant
        if ( ! ${?nlayer00} ) then 
            set nlayer00 = ${nlayer}
        else if ( ${nlayer00} != ${nlayer} ) then
            echo "** ERROR, varied layer depth: ${nlayer00} vs ${nlayer}"
            exit -1
        endif

        cd ${dir_basic}/${dir}/${subjpa}

        # ----- check for necessary files (*** chosen by user ***)
        set HAVE_ALL = 1

        set taskname = rest
        set label    = task-${taskname}
        set label = ""

        set dset = `find ./func -name "sub*${label}*bold.nii*"`
        echo "   ${#dset} sub*${label}*bold.nii*"
        if ( ! ${#dset} ) then
            set HAVE_ALL = 0
        endif

        set dset = `find ./anat -name "sub*T1w.nii*"`
        echo "   ${#dset} sub*T1w.nii*"
        if ( ! ${#dset} ) then
            set HAVE_ALL = 0
        endif

        # ... and add to either the run or skip list
        if ( $HAVE_ALL ) then
            echo "   ... adding"
            echo "${subjli}"         >> ${ftmp_run}
        else
            echo "     - IGNORED"
            echo "${subjli} $PWD"    >> ${ftmp_skip}
        endif
    end
end


# --------------------------------------------------------------------------

# reformat columns nicely
column -t ${ftmp_run}   > ${file_run}
column -t ${ftmp_skip}  > ${file_skip}
column -t ${ftmp_empty} > ${file_empty}

# count used/unused
set nrun  = `cat ${file_run} | wc -l`
@   nskip = ${ncheck} - ${nrun}

# ... and clean up temp files
\rm -f ${ftmp_run}
\rm -f ${ftmp_skip}
\rm -f ${ftmp_empty}

# --------------------------------------------------------------------------
# format and report results

# percentages unused/used
set perc_run   = `echo "scale=1; 100 * ${nrun}  / (1.0 * ${ncheck})" | bc`
set perc_skip  = `echo "scale=1; 100 * ${nskip} / (1.0 * ${ncheck})" | bc`

# format versions for report
set form_check = `printf "%d" ${ncheck}`
set form_run   = `printf "%d (%.1f%%)" ${nrun}  ${perc_run}`
set form_skip  = `printf "%d (%.1f%%)" ${nskip} ${perc_skip}`

# summary comments
if ( ${nempty} ) then
    set topdir_rating = "** warning, need to check"
else
    set topdir_rating = "good"
endif

if ( ${nskip} ) then
    set func_rating = "** warning, need to check"
else
    set func_rating = "good"
endif

# main summary
cat <<EOF
----------------------------------------------------------
++ Done.  Summary:

   Number of layers         : ${nlayer}
   Example subj layer list  : ${subjli}

   Number of top dirs       : ${#all_dir}
   Number of empty top dirs : ${nempty}
                         ---> ${topdir_rating}

   Number of func checked   : ${form_check}
   Number of func added     : ${form_run}
   Number of func ignored   : ${form_skip}
                         ---> ${func_rating}

   Final list file to run:

     cat ${file_run}

EOF

# secondary summary, if any were skipped
if ( ${nempty} ) then
cat <<EOF
   ... and the empty top dirs:

     cat ${file_empty}

EOF
endif

if ( ${nskip} ) then
cat <<EOF
   ... and the func dirs to skip:

     cat ${file_skip}

EOF
endif

exit 0
