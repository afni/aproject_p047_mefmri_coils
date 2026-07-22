#!/bin/usr/env python

# A simple adjunct script to parse various elements of a "subj list",
# which can be composed of: subj, ses, site
# 
# INPUT:  a subject list
#
# OUTPUT: 
#    + an integer representing success (0) or failure (nonzero)
#    + a subjid : subject ID (has underscores connecting list pieces)
#    + a subjpa : subject path (has slashes connecting list pieces)

import sys

# ----------------------------------------------------------------------------

if __name__ == "__main__" :

    # cmd line args
    subjli = sys.argv[1:]
    narg   = len(subjli)
    str_subjli = ' '.join(subjli)

    # set subject ID
    if not(narg) :
        print(-1)
        sys.exit(-1)
    elif narg < 3 :
        # subj or subj_ses
        subjid = '_'.join(subjli)
    elif narg == 3 :
        # site_subj_ses
        subjid = '_'.join(subjli[1:])
    else:
        print(-2)
        sys.exit(-2)

    # set subject data path
    subjpa = '/'.join(subjli)

    print(0, subjid, subjpa)

    sys.exit(0)
