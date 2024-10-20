FROM mcr.microsoft.com/mssql/server:latest

# Switch to root for installing packages
USER root

# Install dependencies, PowerShell, Python pip, Git, and cleanup in one go
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    powershell python3-pip git libsndfile1 && \
    python3 -m pip install aider-chat && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
ENV GIT_PROMPT_START='\033[1;36dbatools>\033[0m\033[0;33m\w\a\033[0m'

# Save command line history
RUN echo "export HISTFILE=/commandhistory/.bash_history" >> "/root/.bashrc" \
    && echo "export PROMPT_COMMAND='history -a'" >> "/root/.bashrc" \
    && mkdir -p /commandhistory \
    && touch /commandhistory/.bash_history \
    && mkdir /workspace

SHELL ["/opt/microsoft/powershell/7/pwsh", "-c"]
RUN Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install Pester, has to be 4.4.3 because 4.4.2 has bug in Unix machines
SHELL ["/opt/microsoft/powershell/7/pwsh", "-c"]
RUN $ErrorActionPreference='Stop'; Install-Module -Name Pester -Force -SkipPublisherCheck -MaximumVersion 4.4.3;

# Install PSScriptAnalyzer
SHELL ["/opt/microsoft/powershell/7/pwsh", "-c"]
RUN $ErrorActionPreference='Stop'; Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck -MaximumVersion 1.18.2;

# Git command prompt
# Change this if you want to utilize your fork
RUN git clone https://github.com/dataplat/dbatools.git ~/.bash-git-prompt --depth=1 \
    && echo "if [ -f \"$HOME/.bash-git-prompt/gitprompt.sh\" ]; then GIT_PROMPT_ONLY_IN_REPO=1 && source $HOME/.bash-git-prompt/gitprompt.sh; fi" >> "/root/.bashrc"
