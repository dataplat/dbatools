function Update-DbaLocalCachedSoftware {
    <#
    .SYNOPSIS
        Download and extract software from Github to update the local cached version of that software.

    .DESCRIPTION
        Download and extract software from Github to update the local cached version of that software.
        This command is run from inside of Install-Dba* and Update-Dba* commands to update the local cache if needed.

    .PARAMETER Software
        Name of the software to download.
        Options include:
        * MaintenanceSolution: SQL Server Maintenance Solution created by Ola Hallengren (https://ola.hallengren.com)
        * FirstResponderKit: First Responder Kit created by Brent Ozar (http://FirstResponderKit.org)
        * DarlingData: Erik Darling's stored procedures (https://www.erikdarlingdata.com)

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
         https://dbatools.io/Update-DbaLocalCachedSoftware

    .EXAMPLE
        PS C:\> Update-DbaLocalCachedSoftware -Software MaintenanceSolution

        Updates the local cache of Ola Hallengren's Solution objects.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [ValidateSet('MaintenanceSolution', 'FirstResponderKit', 'DarlingData')]
        [string]$Software,
        [string]$Branch,
        [string]$LocalFile,
        [string]$Url,
        [string]$LocalDirectory,
        [switch]$EnableException
    )

    $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"

    # Set Branch, Url and LocalDirectory for known Software
    if ($Software -eq 'MaintenanceSolution') {
        if (-not $Branch) {
            $Branch = 'master'
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
            $Branch = 'master'
        }
        if (-not $Url) {
            $Url = "https://github.com/erikdarlingdata/DarlingData/archive/$Branch.zip"
        }
        if (-not $LocalDirectory) {
            $LocalDirectory = Join-Path -Path $dbatoolsData -ChildPath "DarlingData-$Branch"
        }
    }

    # Test if we now have Url and LocalDirectory
    if (-not $Url) {
        Stop-Function -Message 'Url is missing.'
        return
    }
    if (-not $LocalDirectory) {
        Stop-Function -Message 'LocalDirectory is missing.'
        return
    }

    # First part is download and extract and we use the temp directory for that and clean up afterwards.
    # So we use a file and a folder with a random name to reduce potential conflicts,
    # but name them with dbatools to be able to recognize them.
    $temp = [System.IO.Path]::GetTempPath()
    $random = Get-Random
    $zipFile = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random.zip"
    $zipFolder = Join-DbaPath -Path $temp -Child "dbatools_software_download_$random"

    if ($LocalFile) {
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
                Unblock-File $LocalFile -ErrorAction SilentlyContinue
                Expand-Archive -LiteralPath $LocalFile -DestinationPath $zipFolder -Force -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to extract $LocalFile to $zipFolder." -ErrorRecord $_
                return
            }
        }
    } else {
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
                Unblock-File $zipFile -ErrorAction SilentlyContinue
                Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to extract $zipFile to $zipFolder." -ErrorRecord $_
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                return
            }
        }
    }

    # As a safety net, we test whether the archive contained exactly the desired destination directory.
    if ($PSCmdlet.ShouldProcess($zipFolder, "Testing for correct content")) {
        $localDirectoryBase = Split-Path -Path $LocalDirectory
        $localDirectoryName = Split-Path -Path $LocalDirectory -Leaf
        $sourceDirectory = Get-ChildItem -Path $zipFolder -Directory
        $sourceDirectoryName = $sourceDirectory.Name
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
            Copy-Item -Path $sourceDirectory -Destination $localDirectoryBase -Recurse -ErrorAction Stop
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