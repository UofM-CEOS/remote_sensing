#! /bin/bash
# Commentary:
#
# CEOS areas of interest.
# -------------------------------------------------------------------------
# Code:
GMT=GMTdev

#_ + Custom vars ----------------------------------------------------------

# Arrays with WESN coordinates
# Overall plot
REG=( -170 -50 50 85 )
GMTREG=${REG[0]}/${REG[1]}/${REG[2]}/${REG[3]}
GMTPROJ=B$(gmt_get_centred_aea ${REG[0]} ${REG[1]} ${REG[2]} ${REG[3]} | \
		  awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/15c
PSFILENAME=ceos_aoi.ps
# LEGENDFILENAME=~/Documents/Presentations/ArcticNet/HudsonBay/bathy_legend.ps

# Nares
NAR_REG=( -82.5 -55.5 75.6 83 )
# NAR_GMTREG=${NAR_REG[0]}/${NAR_REG[2]}/${NAR_REG[1]}/${NAR_REG[3]}r
NAR_GMTREG=${NAR_REG[0]}/${NAR_REG[1]}/${NAR_REG[2]}/${NAR_REG[3]}
NAR_PROJ=B$(gmt_get_centred_aea ${NAR_REG[0]} ${NAR_REG[1]} \
				${NAR_REG[2]} ${NAR_REG[3]} | \
		   awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/10c
# Baffin Bay
BAF_REG=( -75 -60 61 75.6 )
# NAR_GMTREG=${NAR_REG[0]}/${NAR_REG[2]}/${NAR_REG[1]}/${NAR_REG[3]}r
BAF_GMTREG=${BAF_REG[0]}/${BAF_REG[1]}/${BAF_REG[2]}/${BAF_REG[3]}
BAF_PROJ=B$(gmt_get_centred_aea ${BAF_REG[0]} ${BAF_REG[1]} \
				${BAF_REG[2]} ${BAF_REG[3]} | \
		   awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/8c
# Hudson Bay / Foxe Basin
HUD_REG=( -95.5 -71.5 50.6 75 )
# HUD_GMTREG=${HUD_REG[0]}/${HUD_REG[2]}/${HUD_REG[1]}/${HUD_REG[3]}r
HUD_GMTREG=${HUD_REG[0]}/${HUD_REG[1]}/${HUD_REG[2]}/${HUD_REG[3]}
HUD_PROJ=B$(gmt_get_centred_aea ${HUD_REG[0]} ${HUD_REG[1]} \
				${HUD_REG[2]} ${HUD_REG[3]} | \
		   awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/8c
# Central Arctic
CTR_REG=( -130 -75 66 83 )
# CTR_GMTREG=${CTR_REG[0]}/${CTR_REG[2]}/${CTR_REG[1]}/${CTR_REG[3]}r
CTR_GMTREG=${CTR_REG[0]}/${CTR_REG[1]}/${CTR_REG[2]}/${CTR_REG[3]}
CTR_PROJ=B$(gmt_get_centred_aea ${CTR_REG[0]} ${CTR_REG[1]} \
				${CTR_REG[2]} ${CTR_REG[3]} | \
		   awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/12c
# Beaufort Sea
BEA_REG=( -170 -120 68.5 80 )
# CTR_GMTREG=${CTR_REG[0]}/${CTR_REG[2]}/${CTR_REG[1]}/${CTR_REG[3]}r
BEA_GMTREG=${BEA_REG[0]}/${BEA_REG[1]}/${BEA_REG[2]}/${BEA_REG[3]}
BEA_PROJ=B$(gmt_get_centred_aea ${BEA_REG[0]} ${BEA_REG[1]} \
				${BEA_REG[2]} ${BEA_REG[3]} | \
		   awk 'BEGIN {OFS="/"}; {print $1,$2,$3,$4}')/12c

${GMT} gmtset MAP_FRAME_TYPE=fancy MAP_FRAME_WIDTH=0.1c \
       FONT_ANNOT_PRIMARY=8p

# General overview plot
${GMT} pscoast -R${GMTREG} -J${GMTPROJ} -Wfaint -Di -A0/0/1 \
       --MAP_FRAME_TYPE=plain -K > ${PSFILENAME}
echo ${NAR_REG[0]} ${NAR_REG[1]} ${NAR_REG[2]} ${NAR_REG[3]} | \
    awk '{print $1, $3; print $1, $4; print $2, $4; print $2, $3}' | \
    ${GMT} psxy -R${GMTREG} -J${GMTPROJ} -Am -L -W1p -O -K >> ${PSFILENAME}
echo ${BAF_REG[0]} ${BAF_REG[1]} ${BAF_REG[2]} ${BAF_REG[3]} | \
    awk '{print $1, $3; print $1, $4; print $2, $4; print $2, $3}' | \
    ${GMT} psxy -R${GMTREG} -J${GMTPROJ} -Am -L -W1p -O -K >> ${PSFILENAME}
echo ${HUD_REG[0]} ${HUD_REG[1]} ${HUD_REG[2]} ${HUD_REG[3]} | \
    awk '{print $1, $3; print $1, $4; print $2, $4; print $2, $3}' | \
    ${GMT} psxy -R${GMTREG} -J${GMTPROJ} -Am -L -W1p -O -K >> ${PSFILENAME}
echo ${CTR_REG[0]} ${CTR_REG[1]} ${CTR_REG[2]} ${CTR_REG[3]} | \
    awk '{print $1, $3; print $1, $4; print $2, $4; print $2, $3}' | \
    ${GMT} psxy -R${GMTREG} -J${GMTPROJ} -Am -L -W1p -O -K >> ${PSFILENAME}
echo ${BEA_REG[0]} ${BEA_REG[1]} ${BEA_REG[2]} ${BEA_REG[3]} | \
    awk '{print $1, $3; print $1, $4; print $2, $4; print $2, $3}' | \
    ${GMT} psxy -R${GMTREG} -J${GMTPROJ} -Am -L -W1p -O >> ${PSFILENAME}

# AOIs
${GMT} pscoast -R${NAR_GMTREG} -J${NAR_PROJ} -B4/1WeSn -Wfaint -Df -A0/0/1 \
       -G235/235/210 --MAP_ANNOT_OBLIQUE=1 \
       > Nares_Strait/${PSFILENAME%.ps}_nares.ps
${GMT} pscoast -R${BAF_GMTREG} -J${BAF_PROJ} -B4/2WeSn -Wfaint -Df -A0/0/1 \
       -G235/235/210 --MAP_ANNOT_OBLIQUE=1 \
       > Baffin_Bay/${PSFILENAME%.ps}_baffin.ps
${GMT} pscoast -R${HUD_GMTREG} -J${HUD_PROJ} -B4/5WeSn -Wfaint -Df -A0/0/1 \
       -G235/235/210 --MAP_ANNOT_OBLIQUE=1 \
       > Hudson_Bay/${PSFILENAME%.ps}_hudson.ps
${GMT} pscoast -R${CTR_GMTREG} -J${CTR_PROJ} -B10/5WeSn -Wfaint -Df -A0/0/1 \
       -G235/235/210 --MAP_ANNOT_OBLIQUE=1 \
       > Central_Arctic/${PSFILENAME%.ps}_central.ps
${GMT} pscoast -R${BEA_GMTREG} -J${BEA_PROJ} -B10/2WeSn -Wfaint -Df -A0/0/1 \
       -G235/235/210 --MAP_ANNOT_OBLIQUE=1 \
       > Beaufort_Sea/${PSFILENAME%.ps}_beaufort.ps

# ${GMT} ps2raster -A -P -TF -F${PSFILENAME%.ps} ${PSFILENAME} \
#        ${PSFILENAME%.ps}_nares.ps ${PSFILENAME%.ps}_hudson.ps \
#        ${PSFILENAME%.ps}_central.ps ${PSFILENAME%.ps}_beaufort.ps
${GMT} ps2raster -A -P -Tf ${PSFILENAME} \
       Nares_Strait/${PSFILENAME%.ps}_nares.ps \
       Baffin_Bay/${PSFILENAME%.ps}_baffin.ps \
       Hudson_Bay/${PSFILENAME%.ps}_hudson.ps \
       Central_Arctic/${PSFILENAME%.ps}_central.ps \
       Beaufort_Sea/${PSFILENAME%.ps}_beaufort.ps


#_ + Clean up -------------------------------------------------------------
rm ${PSFILENAME%.ps}*.ps */${PSFILENAME%.ps}*.ps

# -------------------------------------------------------------------------
# phispida_hudsonb.sh ends here
