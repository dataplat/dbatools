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
        Name of the software to download.
        Options include:
        * MaintenanceSolution: SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
        * FirstResponderKit: First Responder Kit created by Brent Ozar (http://FirstResponderKit.org)
        * DarlingData: Erik Darling's stored procedures (https://www.erikdarlingdata.com)
        * SQLWATCH: SQL Server Monitoring Solution created by Marcin Gminski (https://sqlwatch.io/)
        * WhoIsActive: Adam Machanic's comprehensive activity monitoring stored procedure sp_WhoIsActive (https://github.com/amachanic/sp_whoisactive)
        * DbaMultiTool: John McCall's T-SQL scripts for the long haul: optimizing storage, on-the-fly documentation, and general administrative needs (https://dba-multitool.org)
        * AzSqlTips: Azure SQL PM team scripts to review Azure SQL Database design, health and performance.

    .PARAMETER Branch
        Specifies the branch. Defaults to master or main. Can only be used if Software is used.

    .PARAMETER LocalFile
        Specifies the path to a local file to install from instead of downloading from Github.

    .PARAMETER Url
        Specifies the URL to download from. Is not needed if Software is used.

    .PARAMETER LocalDirectory
        Specifies the local directory to extract the downloaded file to. Is not needed if Software is used.

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

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software MaintenanceSolution

        Updates the local cache of Ola Hallengren's Solution objects.

    .EXAMPLE
        PS C:\> Save-DbaCommunitySoftware -Software FirstResponderKit -LocalFile \\fileserver\Software\SQL-Server-First-Responder-Kit-20211106.zip

        Updates the local cache of the First Responder Kit based on the given file.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [ValidateSet('MaintenanceSolution', 'FirstResponderKit', 'DarlingData', 'SQLWATCH', 'WhoIsActive', 'DbaMultiTool', 'AzSqlTips')]
        [string]$Software,
        [string]$Branch,
        [string]$LocalFile,
        [string]$Url,
        [string]$LocalDirectory,
        [switch]$EnableException
    )

    process {
        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

        # Set Branch, Url and LocalDirectory for known Software
        if ($Software -eq 'MaintenanceSolution') {
            if (-not $Branch) {
                $Branch = 'main'
            }
            if (-not $Url) {
                $Url = "https://github.com/olahallengren/sql-server-maintenance-solution/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "sql-server-maintenance-solution-$Branch"
            }
        } elseif ($Software -eq 'FirstResponderKit') {
            if (-not $Branch) {
                $Branch = 'main'
            }
            if (-not $Url) {
                $Url = "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQL-Server-First-Responder-Kit-$Branch"
            }
        } elseif ($Software -eq 'DarlingData') {
            if (-not $Branch) {
                $Branch = 'main'
            }
            if (-not $Url) {
                $Url = "https://github.com/erikdarlingdata/DarlingData/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "DarlingData-$Branch"
            }
        } elseif ($Software -eq 'SQLWATCH') {
            if ($Branch -in 'prerelease', 'pre-release') {
                $preRelease = $true
            } else {
                $preRelease = $false
            }
            if (-not $Url -and -not $LocalFile) {
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
                    return
                }
                $latestRelease = ($releasesJson | ConvertFrom-Json) | Where-Object prerelease -eq $preRelease | Select-Object -First 1
                if ($null -eq $latestRelease) {
                    Stop-Function -Message "No release found."
                    return
                }
                $Url = $latestRelease.assets[0].browser_download_url
            }
            if (-not $LocalDirectory) {
                if ($preRelease) {
                    $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH-prerelease"
                } else {
                    $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "SQLWATCH"
                }
            }
        } elseif ($Software -eq 'WhoIsActive') {
            # We currently ignore -Branch as there is only one branch and there are no pre-releases.
            if (-not $Url -and -not $LocalFile) {
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
                    return
                }
                $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
                if ($null -eq $latestRelease) {
                    Stop-Function -Message "No release found."
                    return
                }
                $Url = $latestRelease.zipball_url
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "WhoIsActive"
            }
        } elseif ($Software -eq 'DbaMultiTool') {
            if (-not $Branch) {
                $Branch = 'master'
            }
            if (-not $Url) {
                $Url = "https://github.com/LowlyDBA/dba-multitool/archive/$Branch.zip"
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "dba-multitool-$Branch"
            }
        } elseif ($Software -eq 'AzSqlTips') {
            # We currently ignore -Branch as there is only one branch and there are no pre-releases.
            if (-not $Url -and -not $LocalFile) {
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
                    return
                }
                $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
                if ($null -eq $latestRelease) {
                    Stop-Function -Message "No release found."
                    return
                }
                $Url = $latestRelease.zipball_url
            }
            if (-not $LocalDirectory) {
                $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "AzSqlTips"
            }
        }

        # First part is download and extract and we use the temp directory for that and clean up afterwards.
        # So we use a file and a folder with a random name to reduce potential conflicts,
        # but name them with dbatools to be able to recognize them.
        $temp = [System.IO.Path]::GetTempPath()
        $random = Get-Random
        $zipFile = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random.zip"
        $zipFolder = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random"

        if ($Software -eq 'WhoIsActive' -and $LocalFile.EndsWith('.sql')) {
            # For WhoIsActive, we allow to pass in the sp_WhoIsActive.sql file or any other sql file with the source code.
            # We create the zip folder with a subfolder named WhoIsActive and copy the LocalFile there as sp_WhoIsActive.sql.
            $appFolder = Join-DbaPath -Path $zipFolder -Child 'WhoIsActive'
            $appFile = Join-DbaPath -Path $appFolder -Child 'sp_WhoIsActive.sql'
            $null = New-Item -Path $zipFolder -ItemType Directory
            $null = New-Item -Path $appFolder -ItemType Directory
            Copy-Item -Path $LocalFile -Destination $appFile
        } elseif ($Software -eq 'AzSqlTips' -and $LocalFile.EndsWith('.sql')) {
            # For AzSqlTips, we allow to pass in the get-sqldb-tips.sql file or any other sql file with the source code.
            # We create the zip folder with a subfolder named AzSqlTips and copy the LocalFile there as get-sqldb-tips.sql.
            $appFolder = Join-DbaPath -Path $zipFolder -Child 'AzSqlTips\sqldb-tips'
            $appFile = Join-DbaPath -Path $appFolder -Child 'get-sqldb-tips.sql'
            $null = New-Item -Path $zipFolder -ItemType Directory
            $null = New-Item -Path $appFolder -ItemType Directory
            Copy-Item -Path $LocalFile -Destination $appFile

        } elseif ($LocalFile) {
            # No download, so we just extract the given file if it exists and is a zip file.
            if (-not (Test-Path $LocalFile)) {
                Stop-Function -Message "$LocalFile doesn't exist"
                return
            }
            if (-not ($LocalFile.EndsWith('.zip'))) {
                Stop-Function -Message "$LocalFile has to be a zip file"
                return
            }
            if ($PSCmdlet.ShouldProcess($LocalFile, "Extracting archive to $zipFolder path")) {
                try {
                    if (-not $IsLinux -and -not $isMac) {
                        Unblock-File $LocalFile -ErrorAction SilentlyContinue
                    }
                    Expand-Archive -LiteralPath $LocalFile -DestinationPath $zipFolder -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Unable to extract $LocalFile to $zipFolder." -ErrorRecord $_
                    return
                }
            }
        } else {
            if (-not $Url) {
                Stop-Function -Message "Url not found. Did you specify any -Software?"
                return
            }
            # Download and extract.
            if ($PSCmdlet.ShouldProcess($Url, "Downloading to $zipFile")) {
                try {
                    try {
                        Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                    } catch {
                        # Try with default proxy and usersettings
                        (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                        Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                    }
                } catch {
                    Stop-Function -Message "Unable to download $Url to $zipFile." -ErrorRecord $_
                    return
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
                    return
                }
            }
        }

        # As a safety net, we test whether the archive contained exactly the desired destination directory.
        # But inside of zip files that are downloaded by the user via a webbrowser and not the api,
        # the directory name is the name of the zip file. So we have to test for that as well.
        if ($PSCmdlet.ShouldProcess($zipFolder, "Testing for correct content")) {
            $localDirectoryBase = Split-Path -Path $LocalDirectory
            $localDirectoryName = Split-Path -Path $LocalDirectory -Leaf
            $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
            $sourceDirectoryName = $sourceDirectory.Name
            if ($Software -eq 'SQLWATCH') {
                # As this software is downloaded as a release, the directory has a different name.
                # Rename the directory from like 'SQLWATCH 4.3.0.23725 20210721131116' to 'SQLWATCH' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'SQLWATCH*') {
                    # Write a file with version info, to be able to check if version is outdated
                    Set-Content -Path "$($sourceDirectory.FullName)\version.txt" -Value $sourceDirectoryName
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'SQLWATCH'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'WhoIsActive') {
                # As this software is downloaded as a release, the directory has a different name.
                # Rename the directory from like 'amachanic-sp_whoisactive-459d2bc' to 'WhoIsActive' to be able to handle this like the other software.
                if ($sourceDirectoryName -like '*sp_whoisactive-*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'WhoIsActive'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'FirstResponderKit') {
                # As this software is downloadable as a release, the directory might have a different name.
                # Rename the directory from like 'SQL-Server-First-Responder-Kit-20211106' to 'SQL-Server-First-Responder-Kit-main' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'SQL-Server-First-Responder-Kit-20*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'SQL-Server-First-Responder-Kit-main'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'DbaMultiTool') {
                # As this software is downloadable as a release, the directory might have a different name.
                # Rename the directory from like 'dba-multitool-1.7.5' to 'dba-multitool-master' to be able to handle this like the other software.
                if ($sourceDirectoryName -like 'dba-multitool-[0-9]*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'dba-multitool-master'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            } elseif ($Software -eq 'AzSqlTips') {
                # As this software is downloaded as a release, the directory has a different name.
                # copy the sqldb-tips directory from like 'azure-sql-tips-1.10.zip' to 'AzSqlTips' to be able to handle this like the other software.
                if ($sourceDirectoryName -like '*azure-sql-tips-*') {
                    Rename-Item -Path $sourceDirectory.FullName -NewName 'AzSqlTips'
                    $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
                    $sourceDirectoryName = $sourceDirectory.Name
                }
            }

            if ($sourceDirectoryName -ne $localDirectoryName) {
                if (Test-Path -PathType Container -Path $LocalDirectory) {
                    $localDirectoryBase = $LocalDirectory
                    $localDirectoryName = $LocalDirectory = $sourceDirectoryName
                } else {
                    Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName, and $LocalDirectory is not a folder."
                    Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                    Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                    return
                }
            }

            if ((Get-ChildItem -Path $zipFolder).Count -gt 1 -or $sourceDirectoryName -ne $localDirectoryName) {
                Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName."
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
        }

        # Replace the target directory by the extracted directory.
        if ($PSCmdlet.ShouldProcess($zipFolder, "Copying content to $LocalDirectory")) {
            try {
                if (Test-Path -Path $LocalDirectory) {
                    Remove-Item -Path $LocalDirectory -Recurse -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Unable to remove the old target directory $LocalDirectory." -ErrorRecord $_
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
            try {
                Copy-Item -Path $sourceDirectory.FullName -Destination $localDirectoryBase -Recurse -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to copy the directory $sourceDirectory to the target directory $localDirectoryBase." -ErrorRecord $_
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
        }

        if ($PSCmdlet.ShouldProcess($zipFile, "Removing temporary file")) {
            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
        }
        if ($PSCmdlet.ShouldProcess($zipFolder, "Removing temporary folder")) {
            Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
        }
    }
}