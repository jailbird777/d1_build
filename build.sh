#/bin/sh
# Author. Tim Molteno tim@molteno.net
# (C) 2022.

ROOT_FS=/builder/rv64-port

chroot ${ROOT_FS} /multistrap_config.sh

# cp stage1.sh ${ROOT_FS}/stage1.sh
# chroot ${ROOT_FS} /stage1.sh

#  Move files we'll need from inside the container to the users directory /outport
#  These files will all be visible in ~/port/ after the script is finished.

cp -a ./ /outport/

# Run the script to create the disk image
./create_image.sh /outport
