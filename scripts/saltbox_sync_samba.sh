# rclone copy /mnt/remote/media/Media/ \
# :smb,host='feiniu.hereisderek.dpdns.org',port=4445,user='asd1234',pass='1dS934dGKnBdnXLAqn8Vu6qGsHRyEq4':/media/ \
# --include "/Movies/**" \
# --include "/Music/**" \
# --include "/TV/**" \
# --progress --size-only --checkers 8 --transfers 8


# rclone copy /mnt/remote/media/Media/ \
# :smb,host='240e:390:5f66:b010:6c48:a042:ac38:ab8',port=4445,user='asd1234',pass='1dS934dGKnBdnXLAqn8Vu6qGsHRyEq4':/media/ \
# --include "/Movies/**" \
# --include "/Music/library/**" \
# --include "/TV/**" \
# --progress --size-only


# rclone copy /mnt/remote/media/Media/ \
# feiniu-ipv6:/media/ \
# --include "/Movies/**" \
# --include "/Music/library/**" \
# --include "/TV/**" \
# --progress --size-only --checkers 8 --transfers 8

rclone copy /mnt/remote/media/Media/ \
feiniu:/media/ \
--include "/Movies/**" \
--include "/Music/library/**" \
--include "/TV/**" \
--progress --size-only --checkers 8 --transfers 8