# Dump the whole design to an SHM database. simvision needs a display, so a
# non-interactive run reports the database path instead of opening a viewer.
database -open waves -into waves.shm -default
probe -create hdlTop -depth all -all -memories -shm
run
exit
