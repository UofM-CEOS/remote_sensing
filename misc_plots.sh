#! /bin/bash
# Commentary:
#
# Some simple maps
# -------------------------------------------------------------------------
# Code:

#_ + Custom vars ----------------------------------------------------------
REG=-115/60/-65/80r
PROJ=B-85/70/65/75/6c
REGARCTIC=240/300/65/80
PROJARCTIC=B270/72.5/65/75/14c
PSFILENAME=~/Documents/Presentations/ArcticNet/TPapakyriakou/map_figure.ps
LEGENDFILENAME=~/Documents/Presentations/ArcticNet/HudsonBay/bathy_legend.ps
GMT=GMTdev

${GMT} makecpt -T100/450/5 -Z > pco2.cpt

${GMT} pscoast -R${REGARCTIC} -J${PROJARCTIC} -B10/5 -Wfaint \
       -A0/0/1 -K > leg1.ps
awk -F, 'FNR > 1 {print $4, $3, $5}' LLeg1.csv | \
    ${GMT} psxy -R -J -Cpco2.cpt -Sc2p -O -K >> leg1.ps
${GMT} psscale -D-1c/-9c/8c/0.3ch -Cpco2.cpt -B50f50:"pCO2": -Xc -Yc \
    --MAP_LABEL_OFFSET=1c -O >> leg1.ps

# # The scale we made for the bathymetry
# ${GMT} makecpt -Cocean -T0/500/50 -I -Z > /tmp/junk.cpt
# ${GMT} psscale -D4c/0c/-8c/0.3c -C/tmp/junk.cpt -B100f50:"title": -Xc -Yc \
#     --LABEL_OFFSET=1c > /tmp/junk.ps
# # gv /tmp/junk.ps

# cat <<EOF > .legend
# S 0.2c c 5p red - 0.4c Symbol shifts
# EOF
# pscoast -R${REG} -J${PROJ} -B5/2.5 -Wfaint -K > leg_shift.ps
# echo "-83 57" | psxy -R -J -Sc10p -Gred -O >> leg_shift.ps
# pscoast -R${REG} -J${PROJ} -B5/2.5 -Wfaint -K > leg_shift1.ps
# pslegend .legend -Dx0.2c/0.2c/3.5c/1.3c/BL -Gwhite -R -J \
#     -U/0c/-1c -O -K >> leg_shift1.ps
# echo "-83 57" | psxy -R${REG} -J${PROJ} -Sc10p -Gred -O >> leg_shift1.ps

# # A Simple map of area of interest with context
# pscoast -R${REGARCTIC} -J${PROJARCTIC} -Wfaint -A0/0/1 \
#     --BASEMAP_TYPE=plain -G235/235/210 -Slightblue -K > ${PSFILENAME}
# # Small region rectangle
# echo ${REG%r} | \
#     awk -F/ '{
#               print $3-1.7, $2; print $1-1.7, $2;
#               print $1-1.7, $4; print $3-1.7, $4}' | \
#     psxy -R -J -L -W1p -O -K >> ${PSFILENAME}
# pscoast -R${REG} -J${PROJ} -Wfaint -A0/0/1 -X8c \
#     -G235/235/210 -Slightblue --OBLIQUE_ANNOTATION=30 -O >> ${PSFILENAME}
# # pscoast -R${REG} -J${PROJ} -B5/2.5 -Wfaint -K > leg_shift.ps
# ps2raster -A -Tf -P ${PSFILENAME}
# mogrify -density 600 +antialias ${PSFILENAME%.ps}.pdf

# # The scale we made for the behavioural modes (SSM movement of ringed seals):
# makecpt -Csplit -T1/2/0.1 -Z --D_FORMAT=%.6g > /tmp/ssm_bt_scale.cpt
# psscale -D4c/0c/8c/0.3ch -C/tmp/ssm_bt_scale.cpt -I -E \
#     -B0.2:"behaviour mode": --D_FORMAT=%.6g --LABEL_OFFSET=0.1c \
#     --TICK_LENGTH=0.05 -K > ${LEGENDFILENAME}
# cat <<EOF | pstext -JX8c -R0/8/0/1 -O >> ${LEGENDFILENAME}
# 0 0.04 12 0 0 LB traveling
# 8 0.04 12 0 0 RB foraging
# EOF
# ps2raster -A -Tf -P ${LEGENDFILENAME}
# mogrify -density 600 +antialias ${LEGENDFILENAME%.ps}.pdf

# # The scale we made for the bathymetry
# BATHY_CPT=/tmp/dummy_bathy.cpt
# TSPENT_CPT=phispida_hb_tspent_core_msk.cpt
# psscale -D4c/0c/8c/0.3ch -C${BATHY_CPT} -I -E -B500:"bathymetry":/:m: \
#     --D_FORMAT=%.6g --LABEL_OFFSET=0.1c --TICK_LENGTH=0.05 > ${LEGENDFILENAME}
# ps2raster -A -Tf -P ${LEGENDFILENAME}
# mogrify -density 600 +antialias ${LEGENDFILENAME%.ps}.pdf


#_ + Clean up -------------------------------------------------------------
rm ${PSFILENAME} ${LEGENDFILENAME} .gmtcommands4 .gmtdefaults4 .tmp{locs,times}* ffmpeg*.log

# -------------------------------------------------------------------------
# phispida_hudsonb.sh ends here
