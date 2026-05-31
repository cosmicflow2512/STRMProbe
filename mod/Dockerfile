# STRMProbe LinuxServer.io Docker mod.
#
# A Docker mod is just a tarball of files overlaid onto the target container's
# filesystem at startup, before the init logic runs. We ship only shell scripts,
# so no build stage is needed.
#
# The contents of root/ are produced by mod/stage.sh from src/ (single source of
# truth); run `bash mod/stage.sh` (or `bash mod/build.sh`) before building locally.
FROM scratch
COPY root/ /
