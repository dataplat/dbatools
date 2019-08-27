ARG fromTag=6.2.2-ubuntu-18.04
ARG imageRepo=microsft/powershell
ARG modName=dbatools
ARG modVer=1.0.33

FROM ${imageRepo}:${fromTag} AS dbatools-env

RUN apt-get update \
    && apt-get install -y \
    && Set-PSRepository -Name PSGallery -InstallationPolicy Trusted \
    && Install-Module ${modName} -MaximumVersion ${modVer} -Force -Confirm:$false

#Define best practice stuff
ARG VCS_REF="none"
ARG IMAGE_NAME=dbatools.io/dbatools:latest

LABEL maintainer="Shawn Melton <wshawnmelton@outlook.com>" \
    readme.md="https://github.com/sqlcollaborative/dbatools-image/blob/master/docker/README.md" \
    description="This Dockerfile will install latest release of dbatools module"

# must be last line
CMD [ "pwsh" ]