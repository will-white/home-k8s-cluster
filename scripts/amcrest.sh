# ./amcrest.sh <username> <password> <host or IP>

# Turn off amcrest water mark
curl -u $1:$2 "http://$3/cgi-bin/configManager.cgi?action=setConfig&VideoWidget[0].PictureTitle.EncodeBlend=false" -g -X GET --digest
curl -u $1:$2 "http://$3/cgi-bin/configManager.cgi?action=setConfig&VideoWidget[0].PictureTitle.PreviewBlend=false" -g -X GET --digest

# Turn off datetime water mark
curl -u $1:$2 "http://$3/cgi-bin/configManager.cgi?action=setConfig&VideoWidget[0].TimeTitle.EncodeBlend=false" -g -X GET --digest
curl -u $1:$2 "http://$3/cgi-bin/configManager.cgi?action=setConfig&VideoWidget[0].TimeTitle.PreviewBlend=false" -g -X GET --digest

# Keep doorbell alive and maybe awake??
curl -u $1:$2 -X GET --digest "http://$3/cgi-bin/configManager.cgi?action=setConfig&VSP_PaaS.Online=true"
