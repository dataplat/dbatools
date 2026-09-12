function Save-DbaCommunitySoftware {
    <#
    .SYNOPSIS
        Downloads and caches popular SQL Server community tools from GitHub for use by dbatools installation commands

    .DESCRIPTION
        Downloads and extracts popular SQL Server community tools from GitHub repositories to maintain a local cache used by dbatools installation commands.
        This function automatically manages the acquisition and versioning of essential DBA script collections, eliminating the need to manually download and organize multiple tool repositories.
        It's called internally by Install-Dba*, Update-Dba*, and Invoke-DbaAzSqlDbTip commands when they need to access the latest versions of community tools.

        Supports both online downloads directly from GitHub and offline installations using local zip files, making it suitable for restricted network environments.
        The function handles version detection, directory structure normalization, and maintains consistent file organization across different tool repositories.

        For environments without internet access, you can download zip files from the following URLs on another computer, transfer them to the target system, and use -LocalFile to update the local cache:
        * MaintenanceSolution: https://github.com/olahallengren/sql-server-maintenance-solution
        * FirstResponderKit: https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/releases
        * DarlingData: https://github.com/erikdarlingdata/DarlingData
        * SQLWATCH: https://github.com/marcingminski/sqlwatch/releases
        * WhoIsActive: https://github.com/amachanic/sp_whoisactive/releases
        * DbaMultiTool: https://github.com/LowlyDBA/dba-multitool/releases
        * AzSqlTips: https://github.com/microsoft/azure-sql-tips/releases/

    .PARAMETER Software
        Name of the software to download. Accepts an array to download several tools in one call, or All to download every supported tool.
        Options include:
        * All: Downloads every tool listed below.
        * MaintenanceSolution: SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
        * FirstResponderKit: First Responder Kit created by Brent Ozar (http://FirstResponderKit.org)
        * DarlingData: Erik Darling's stored procedures (https://www.erikdarlingdata.com)
        * SQLWATCH: SQL Server Monitoring Solution created by Marcin Gminski (https://sqlwatch.io/)
        * WhoIsActive: Adam Machanic's comprehensive activity monitoring stored procedure sp_WhoIsActive (https://github.com/amachanic/sp_whoisactive)
        * DbaMultiTool: John McCall's T-SQL scripts for the long haul: optimizing storage, on-the-fly documentation, and general administrative needs (https://dba-multitool.org)
        * AzSqlTips: Azure SQL PM team scripts to review Azure SQL Database design, health and performance.

        Url, LocalFile and LocalDirectory only apply to a single tool, so they cannot be combined with more than one Software value, including All.

    .PARAMETER Branch
        Specifies which branch or version to download from the GitHub repository. Defaults to main.
        Use this when you need a specific development branch or to override default versioning. Only applies to branch-based downloads like MaintenanceSolution, FirstResponderKit, DarlingData, and DbaMultiTool.
        For SQLWATCH, use "prerelease" or "pre-release" to get preview versions instead of stable releases.

    .PARAMETER LocalFile
        Specifies the path to a local zip file or SQL script to install from instead of downloading from GitHub.
        Use this for offline environments or when you have a specific version already downloaded. Accepts zip archives for all tools, plus individual SQL files for WhoIsActive (sp_WhoIsActive.sql) and AzSqlTips (get-sqldb-tips.sql).
        Essential for air-gapped systems where direct internet access is not available.

    .PARAMETER Url
        Specifies a custom URL to download the software archive from instead of using the automatic GitHub URLs.
        Use this when you need to download from a forked repository, specific release, or alternative hosting location. Overrides the default URL generation that occurs when using the Software parameter.
        Must point to a downloadable zip file containing the community tools.

    .PARAMETER LocalDirectory
        Specifies a custom directory path where the community software will be extracted and cached.
        Use this when you need to store the tools in a non-standard location instead of the default dbatools data directory. Overrides the automatic path generation based on the Software parameter.
        Useful for custom cache locations or when working with multiple versions of the same tool.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community
        Author: Andreas Jordan, @JordanOrdix

        Website: https://dbatools.io
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
         https://dbatools.io/Save-DbaCommunitySoftware

    .OUTPUTS
        None

        This command does not output any objects to the pipeline. It performs file operations to download and extract community software tools to the local cache directory. To verify successful operation, check the exit code or use ErrorAction/ErrorVariable parameters.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software MaintenanceSolution

        Updates the local cache of Ola Hallengren's Solution objects.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software FirstResponderKit -LocalFile \\fileserver\Software\SQL-Server-First-Responder-Kit-20211106.zip

        Updates the local cache of the First Responder Kit based on the given file.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software MaintenanceSolution, FirstResponderKit, DarlingData

        Updates the local cache of each of the three named tools.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software All

        Updates the local cache of every supported community tool.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [ValidateSet("All", "MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool", "AzSqlTips")]
        [string[]]$Software,
        [string]$Branch,
        [string]$LocalFile,
        [string]$Url,
        [string]$LocalDirectory,
        [switch]$EnableException
    )

    process {
        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        $allSoftware = @("MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool", "AzSqlTips")

        if ($Software -contains "All") {
            $softwareList = $allSoftware
        } elseif ($Software) {
            $softwareList = $Software | Select-Object -Unique
        } else {
            $softwareList = @($null)
        }

        # Url, LocalFile and LocalDirectory each describe a single tool, so they cannot be reused across multiple Software values.
        if ($softwareList.Count -gt 1 -and ($Url -or $LocalFile -or $LocalDirectory)) {
            Stop-Function -Message "Url, LocalFile and LocalDirectory can only be used together with a single -Software value."
            return
        }

        :softwareLoop foreach ($currentSoftware in $softwareList) {
            $currentBranch = $Branch
            $currentUrl = $Url
            $currentLocalDirectory = $LocalDirectory

            # Set Branch, Url and LocalDirectory for known Software
            if ($currentSoftware -eq "MaintenanceSolution") {
                if (-not $currentBranch) {
                    $currentBranch = "main"
                }
                if (-not $currentUrl) {
                    $currentUrl = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/$currentBranch.zip"
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "sql-server-maintenance-solution-$currentBranch"
                }
            } elseif ($currentSoftware -eq "FirstResponderKit") {
                if (-not $currentBranch) {
                    $currentBranch = "main"
                }
                if (-not $currentUrl) {
                    $currentUrl = "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/$currentBranch.zip"
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQL-Server-First-Responder-Kit-$currentBranch"
                }
            } elseif ($currentSoftware -eq "DarlingData") {
                if (-not $currentBranch) {
                    $currentBranch = "main"
                }
                if (-not $currentUrl) {
                    $currentUrl = "https://github.com/erikdarlingdata/DarlingData/archive/$currentBranch.zip"
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "DarlingData-$currentBranch"
                }
            } elseif ($currentSoftware -eq "SQLWATCH") {
                if ($currentBranch -in "prerelease", "pre-release") {
                    $preRelease = $true
                } else {
                    $preRelease = $false
                }
                if (-not $currentUrl -and -not $LocalFile) {
                    $releasesUrl = "https://api.github.com/repos/marcingminski/sqlwatch/releases"
                    try {
                        try {
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        }
                    } catch {
                        Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_
                        continue
                    }
                    $latestRelease = ($releasesJson | ConvertFrom-Json) | Where-Object prerelease -eq $preRelease | Select-Object -First 1
                    if ($null -eq $latestRelease) {
                        Stop-Function -Message "No release found."
                        continue
                    }
                    $currentUrl = $latestRelease.assets[0].browser_download_url
                }
                if (-not $currentLocalDirectory) {
                    if ($preRelease) {
                        $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH-prerelease"
                    } else {
                        $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH"
                    }
                }
            } elseif ($currentSoftware -eq "WhoIsActive") {
                # We currently ignore -Branch as there is only one branch and there are no pre-releases.
                if (-not $currentUrl -and -not $LocalFile) {
                    $releasesUrl = "https://api.github.com/repos/amachanic/sp_whoisactive/releases"
                    try {
                        try {
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        }
                    } catch {
                        Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_
                        continue
                    }
                    $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
                    if ($null -eq $latestRelease) {
                        Stop-Function -Message "No release found."
                        continue
                    }
                    $currentUrl = $latestRelease.zipball_url
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "WhoIsActive"
                }
            } elseif ($currentSoftware -eq "DbaMultiTool") {
                if (-not $currentBranch) {
                    # dba-multitool's default branch on GitHub was renamed from master to main;
                    # the old name no longer resolves to a matching archive folder.
                    $currentBranch = "main"
                }
                if (-not $currentUrl) {
                    $currentUrl = "https://github.com/LowlyDBA/dba-multitool/archive/$currentBranch.zip"
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "dba-multitool-$currentBranch"
                }
            } elseif ($currentSoftware -eq "AzSqlTips") {
                # We currently ignore -Branch as there is only one branch and there are no pre-releases.
                if (-not $currentUrl -and -not $LocalFile) {
                    $releasesUrl = "https://api.github.com/repos/microsoft/azure-sql-tips/releases"
                    try {
                        try {
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        } catch {
                            # Try with default proxy and usersettings
                            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                            $releasesJson = Invoke-TlsWebRequest -Uri $releasesUrl -UseBasicParsing -ErrorAction Stop
                        }
                    } catch {
                        Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_
                        continue
                    }
                    $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
                    if ($null -eq $latestRelease) {
                        Stop-Function -Message "No release found."
                        continue
                    }
                    $currentUrl = $latestRelease.zipball_url
                }
                if (-not $currentLocalDirectory) {
                    $currentLocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "AzSqlTips"
                }
            }

            # First part is download and extract and we use the temp directory for that and clean up afterwards.
            # So we use a file and a folder with a random name to reduce potential conflicts,
            # but name them with dbatools to be able to recognize them.
            $temp = [System.IO.Path]::GetTempPath()
            $random = Get-Random
            $zipFile = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random.zip"
            $zipFolder = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random"

            if ($currentSoftware -eq "WhoIsActive" -and $LocalFile.EndsWith(".sql")) {
                # For WhoIsActive, we allow to pass in the sp_WhoIsActive.sql file or any other sql file with the source code.
                # We create the zip folder with a subfolder named WhoIsActive and copy the LocalFile there as sp_WhoIsActive.sql.
                $appFolder = Join-DbaPath -Path $zipFolder -Child "WhoIsActive"
                $appFile = Join-DbaPath -Path $appFolder -Child "sp_WhoIsActive.sql"
                $null = New-Item -Path $zipFolder -ItemType Directory
                $null = New-Item -Path $appFolder -ItemType Directory
                Copy-Item -Path $LocalFile -Destination $appFile
            } elseif ($currentSoftware -eq "AzSqlTips" -and $LocalFile.EndsWith(".sql")) {
                # For AzSqlTips, we allow to pass in the get-sqldb-tips.sql file or any other sql file with the source code.
                # We create the zip folder with a subfolder named AzSqlTips and copy the LocalFile there as get-sqldb-tips.sql.
                $appFolder = Join-DbaPath -Path $zipFolder -Child "AzSqlTips\sqldb-tips"
                $appFile = Join-DbaPath -Path $appFolder -Child "get-sqldb-tips.sql"
                $null = New-Item -Path $zipFolder -ItemType Directory
                $null = New-Item -Path $appFolder -ItemType Directory
                Copy-Item -Path $LocalFile -Destination $appFile

            } elseif ($LocalFile) {
                # No download, so we just extract the given file if it exists and is a zip file.
                if (-not (Test-Path $LocalFile)) {
                    Stop-Function -Message "$LocalFile doesn't exist"
                    continue
                }
                if (-not ($LocalFile.EndsWith(".zip"))) {
                    Stop-Function -Message "$LocalFile has to be a zip file"
                    continue
                }
                if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $zipFolder path")) {
                    try {
                        if (-not $IsLinux -and -not $isMac) {
                            Unblock-File $LocalFile -ErrorAction SilentlyContinue
                        }
                        Expand-Archive -LiteralPath $LocalFile -DestinationPath $zipFolder -Force -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Unable to extract $LocalFile to $zipFolder." -ErrorRecord $_
                        continue
                    }
                }
            } else {
                if (-not $currentUrl) {
                    Stop-Function -Message "Url not found. Did you specify any -Software?"
                    continue
                }
                # Download and extract.
                if ($PSCmdlet.ShouldProcess($currentUrl, "Downloading to $zipFile")) {
                    # Downloads from GitHub fail transiently now and then (rate limiting, connection resets),
                    # especially on shared CI runners, so retry with a short backoff before giving up.
                    $downloadAttempts = 3
                    foreach ($attempt in 1..$downloadAttempts) {
                        try {
                            try {
                                # Clear any partial file from an earlier request so the existence check
                                # below can only see the file written by this request.
                                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                                Invoke-TlsWebRequest -Uri $currentUrl -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                            } catch {
                                # Try with default proxy and usersettings
                                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                                (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                                Invoke-TlsWebRequest -Uri $currentUrl -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                            }
                            # A download can complete without a terminating error and still not produce the file,
                            # which otherwise surfaces later as a confusing Expand-Archive path error, so treat
                            # a missing file as a failed attempt that is eligible for a retry.
                            if (-not (Test-Path -Path $zipFile)) {
                                throw "Download of $currentUrl completed without error, but $zipFile was not created."
                            }
                            break
                        } catch {
                            # A failed attempt can leave a partial file behind that would mask the failure
                            # or corrupt the next attempt, so clean it up before retrying or giving up.
                            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                            if ($attempt -lt $downloadAttempts) {
                                Write-Message -Level Verbose -Message "Download attempt $attempt of $downloadAttempts for $currentUrl failed, retrying. $PSItem"
                                Start-Sleep -Seconds (2 * $attempt)
                            } else {
                                Stop-Function -Message "Unable to download $currentUrl to $zipFile after $downloadAttempts attempts." -ErrorRecord $_
                                continue softwareLoop
                            }
                        }
                    }
                }
                if ($PSCmdlet.ShouldProcess($zipFile, "Extracting archive to $zipFolder path")) {
                    try {
                        if (-not $IsLinux -and -not $isMac) {
                            Unblock-File $zipFile -ErrorAction SilentlyContinue
                        }

                        Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Unable to extract $zipFile to $zipFolder." -ErrorRecord $_
                        Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                        continue
                    }
                }
            }

            # As a safety net, we test whether the archive contained exactly the desired destination directory.
            # But inside of zip files that are downloaded by the user via a webbrowser and not the api,
            # the directory name is the name of the zip file. So we have to test for that as well.
            if ($PSCmdlet.ShouldProcess($zipFolder, "Testing for correct content")) {
                $localDirectoryBase = Split-Path -Path $currentLocalDirectory
                $localDirectoryName = Split-Path -Path $currentLocalDirectory -Leaf
                $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                $sourceDirectoryName = $sourceDirectory.Name
                if ($currentSoftware -eq "SQLWATCH") {
                    # As this software is downloaded as a release, the directory has a different name.
                    # Rename the directory from like 'SQLWATCH 4.3.0.23725 20210721131116' to 'SQLWATCH' to be able to handle this like the other software.
                    if ($sourceDirectoryName -like "SQLWATCH*") {
                        # Write a file with version info, to be able to check if version is outdated
                        Set-Content -Path "$($sourceDirectory.FullName)\version.txt" -Value $sourceDirectoryName
                        Rename-Item -Path $sourceDirectory.FullName -NewName "SQLWATCH"
                        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                        $sourceDirectoryName = $sourceDirectory.Name
                    }
                } elseif ($currentSoftware -eq "WhoIsActive") {
                    # As this software is downloaded as a release, the directory has a different name.
                    # Rename the directory from like 'amachanic-sp_whoisactive-459d2bc' to 'WhoIsActive' to be able to handle this like the other software.
                    if ($sourceDirectoryName -like "*sp_whoisactive-*") {
                        Rename-Item -Path $sourceDirectory.FullName -NewName "WhoIsActive"
                        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                        $sourceDirectoryName = $sourceDirectory.Name
                    }
                } elseif ($currentSoftware -eq "FirstResponderKit") {
                    # As this software is downloadable as a release, the directory might have a different name.
                    # Rename the directory from like 'SQL-Server-First-Responder-Kit-20211106' to 'SQL-Server-First-Responder-Kit-main' to be able to handle this like the other software.
                    if ($sourceDirectoryName -like "SQL-Server-First-Responder-Kit-20*") {
                        Rename-Item -Path $sourceDirectory.FullName -NewName "SQL-Server-First-Responder-Kit-main"
                        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                        $sourceDirectoryName = $sourceDirectory.Name
                    }
                } elseif ($currentSoftware -eq "DbaMultiTool") {
                    # As this software is downloadable as a release, the directory might have a different name.
                    # Rename the directory from like 'dba-multitool-1.7.5' to 'dba-multitool-main' to be able to handle this like the other software.
                    if ($sourceDirectoryName -like "dba-multitool-[0-9]*") {
                        Rename-Item -Path $sourceDirectory.FullName -NewName "dba-multitool-main"
                        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                        $sourceDirectoryName = $sourceDirectory.Name
                    }
                } elseif ($currentSoftware -eq "AzSqlTips") {
                    # As this software is downloaded as a release, the directory has a different name.
                    # copy the sqldb-tips directory from like 'azure-sql-tips-1.10.zip' to 'AzSqlTips' to be able to handle this like the other software.
                    if ($sourceDirectoryName -like "*azure-sql-tips-*") {
                        Rename-Item -Path $sourceDirectory.FullName -NewName "AzSqlTips"
                        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                        $sourceDirectoryName = $sourceDirectory.Name
                    }
                }

                if ($sourceDirectoryName -ne $localDirectoryName) {
                    if (Test-Path -PathType Container -Path $currentLocalDirectory) {
                        $localDirectoryBase = $currentLocalDirectory
                        $localDirectoryName = $currentLocalDirectory = $sourceDirectoryName
                    } else {
                        Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName, and $currentLocalDirectory is not a folder."
                        Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                        Remove-Item -Path $zipFolder -Recurse -Force -ErrorAction SilentlyContinue
                        continue
                    }
                }

                if ((Get-ChildItem -Path $zipFolder).Count -gt 1 -or $sourceDirectoryName -ne $localDirectoryName) {
                    Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName."
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                    Remove-Item -Path $zipFolder -Recurse -Force -ErrorAction SilentlyContinue
                    continue
                }
            }

            # Replace the target directory by the extracted directory.
            if ($PSCmdlet.ShouldProcess($zipFolder, "Copying content to $currentLocalDirectory")) {
                try {
                    if (Test-Path -Path $currentLocalDirectory) {
                        # -Force is required on macOS/Linux: GitHub archives contain dotfiles
                        # (.github, .gitignore) which PowerShell treats as hidden there, and
                        # Remove-Item refuses hidden items without it.
                        Remove-Item -Path $currentLocalDirectory -Recurse -Force -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Unable to remove the old target directory $currentLocalDirectory." -ErrorRecord $_
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                    Remove-Item -Path $zipFolder -Recurse -Force -ErrorAction SilentlyContinue
                    continue
                }
                try {
                    Copy-Item -Path $sourceDirectory.FullName -Destination $localDirectoryBase -Recurse -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Unable to copy the directory $sourceDirectory to the target directory $localDirectoryBase." -ErrorRecord $_
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                    Remove-Item -Path $zipFolder -Recurse -Force -ErrorAction SilentlyContinue
                    continue
                }
            }

            if ($PSCmdlet.ShouldProcess($zipFile, "Removing temporary file")) {
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
            }
            if ($PSCmdlet.ShouldProcess($zipFolder, "Removing temporary folder")) {
                Remove-Item -Path $zipFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
