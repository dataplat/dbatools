#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Downloads and caches popular SQL Server community tools (Maintenance Solution, First Responder
/// Kit, DarlingData, SQLWATCH, WhoIsActive, DbaMultiTool, AzSqlTips) from GitHub for use by the
/// dbatools install/update commands. The URL resolution, download, extraction, directory
/// normalization, and ShouldProcess flow remain a module-scoped PowerShell compatibility hop; this
/// cmdlet supplies the real ShouldProcess runtime. There is no SqlInstance surface and no pipeline
/// input - the command runs once against the local cache, so the body is a single process-record
/// hop with no cross-record carrier. Surface pinned by
/// migration/baselines/Save-DbaCommunitySoftware.json.
/// </summary>
[Cmdlet(VerbsData.Save, "DbaCommunitySoftware", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SaveDbaCommunitySoftwareCommand : DbaBaseCmdlet
{
    /// <summary>Name of the community software to download and cache.</summary>
    [Parameter(Position = 0)]
    [PsStringCast]
    [ValidateSet("MaintenanceSolution", "FirstResponderKit", "DarlingData", "SQLWATCH", "WhoIsActive", "DbaMultiTool", "AzSqlTips")]
    public string? Software { get; set; }

    /// <summary>The branch or version to download for branch-based repositories.</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    public string? Branch { get; set; }

    /// <summary>Path to a local zip archive or SQL file to install from instead of downloading.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>A custom URL to download the software archive from.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Url { get; set; }

    /// <summary>A custom directory where the software will be extracted and cached.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? LocalDirectory { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Single process record, no cross-record carrier: the command has no SqlInstance surface and
        // no pipeline input, so the whole body runs once. Its Stop-Function branches each `return`
        // from the hop scriptblock, matching the source's `return` from the process block.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            Software, Branch, LocalFile, Url, LocalDirectory, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($Software, $Branch, $LocalFile, $Url, $LocalDirectory, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([string]$Software, [string]$Branch, [string]$LocalFile, [string]$Url, [string]$LocalDirectory, $EnableException, $__realCmdlet)

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
                Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                return
            }
            $latestRelease = ($releasesJson | ConvertFrom-Json) | Where-Object prerelease -eq $preRelease | Select-Object -First 1
            if ($null -eq $latestRelease) {
                Stop-Function -Message "No release found." -FunctionName Save-DbaCommunitySoftware
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
                Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                return
            }
            $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
            if ($null -eq $latestRelease) {
                Stop-Function -Message "No release found." -FunctionName Save-DbaCommunitySoftware
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
                Stop-Function -Message "Unable to get release information from $releasesUrl." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                return
            }
            $latestRelease = ($releasesJson | ConvertFrom-Json) | Select-Object -First 1
            if ($null -eq $latestRelease) {
                Stop-Function -Message "No release found." -FunctionName Save-DbaCommunitySoftware
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
            Stop-Function -Message "$LocalFile doesn't exist" -FunctionName Save-DbaCommunitySoftware
            return
        }
        if (-not ($LocalFile.EndsWith('.zip'))) {
            Stop-Function -Message "$LocalFile has to be a zip file" -FunctionName Save-DbaCommunitySoftware
            return
        }
        if ($__realCmdlet.ShouldProcess($LocalFile, "Extracting archive to $zipFolder path")) {
            try {
                if (-not $IsLinux -and -not $isMac) {
                    Unblock-File $LocalFile -ErrorAction SilentlyContinue
                }
                Expand-Archive -LiteralPath $LocalFile -DestinationPath $zipFolder -Force -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to extract $LocalFile to $zipFolder." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                return
            }
        }
    } else {
        if (-not $Url) {
            Stop-Function -Message "Url not found. Did you specify any -Software?" -FunctionName Save-DbaCommunitySoftware
            return
        }
        # Download and extract.
        if ($__realCmdlet.ShouldProcess($Url, "Downloading to $zipFile")) {
            try {
                try {
                    Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                } catch {
                    # Try with default proxy and usersettings
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    Invoke-TlsWebRequest -Uri $Url -OutFile $zipFile -UseBasicParsing -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Unable to download $Url to $zipFile." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                return
            }
        }
        if ($__realCmdlet.ShouldProcess($zipFile, "Extracting archive to $zipFolder path")) {
            try {
                if (-not $IsLinux -and -not $isMac) {
                    Unblock-File $zipFile -ErrorAction SilentlyContinue
                }

                Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force -ErrorAction Stop
            } catch {
                Stop-Function -Message "Unable to extract $zipFile to $zipFolder." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                return
            }
        }
    }

    # As a safety net, we test whether the archive contained exactly the desired destination directory.
    # But inside of zip files that are downloaded by the user via a webbrowser and not the api,
    # the directory name is the name of the zip file. So we have to test for that as well.
    if ($__realCmdlet.ShouldProcess($zipFolder, "Testing for correct content")) {
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
                Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName, and $LocalDirectory is not a folder." -FunctionName Save-DbaCommunitySoftware
                Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
                Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
                return
            }
        }

        if ((Get-ChildItem -Path $zipFolder).Count -gt 1 -or $sourceDirectoryName -ne $localDirectoryName) {
            Stop-Function -Message "The archive does not contain the desired directory $localDirectoryName but $sourceDirectoryName." -FunctionName Save-DbaCommunitySoftware
            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
            Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
            return
        }
    }

    # Replace the target directory by the extracted directory.
    if ($__realCmdlet.ShouldProcess($zipFolder, "Copying content to $LocalDirectory")) {
        try {
            if (Test-Path -Path $LocalDirectory) {
                Remove-Item -Path $LocalDirectory -Recurse -ErrorAction Stop
            }
        } catch {
            Stop-Function -Message "Unable to remove the old target directory $LocalDirectory." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
            Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
            return
        }
        try {
            Copy-Item -Path $sourceDirectory.FullName -Destination $localDirectoryBase -Recurse -ErrorAction Stop
        } catch {
            Stop-Function -Message "Unable to copy the directory $sourceDirectory to the target directory $localDirectoryBase." -ErrorRecord $_ -FunctionName Save-DbaCommunitySoftware
            Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
            Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
            return
        }
    }

    if ($__realCmdlet.ShouldProcess($zipFile, "Removing temporary file")) {
        Remove-Item -Path $zipFile -ErrorAction SilentlyContinue
    }
    if ($__realCmdlet.ShouldProcess($zipFolder, "Removing temporary folder")) {
        Remove-Item -Path $zipFolder -Recurse -ErrorAction SilentlyContinue
    }
} $Software $Branch $LocalFile $Url $LocalDirectory $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
