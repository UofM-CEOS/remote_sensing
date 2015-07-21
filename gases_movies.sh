#! /bin/bash
# gases_movies.sh --- Animations
# Author: Sebastian Luque
# Created: 2014-03-25T14:52:18+0000
# Last-Updated: 2014-03-26T22:47:09+0000
#           By: Sebastian P. Luque
# -------------------------------------------------------------------------
# Commentary: 
#
# Programs for plotting animations: KML, etc.
# -------------------------------------------------------------------------
# Code:

# Color palette for our data
makecpt -Crainbow -T-5/21/0.1 > /tmp/sst.cpt

# Read and rearrange our data, feed to GMT.
awk -F, '{
    print $2, $3, $4
}' /tmp/daily_20min_2011.csv | \
    gmt2kml -Aax2e4 -E -Fl -Gfseagreen3 -H -K > /tmp/daily_20min_2011.kml
awk -F, '{
    sub(/ /, "T", $1)
    print $2, $3, $4
}' /tmp/daily_20min_2011.csv | \
    gmt2kml -Aax2e4 -Fs -C/tmp/sst.cpt -L2:SST -Sf0.45 -H -O -N \
    >> /tmp/daily_20min_2011.kml



#_ + Emacs local variables
# Local variables:
# allout-layout: (1 + : 0)
# End:
# 
# gases_movies.sh ends here
