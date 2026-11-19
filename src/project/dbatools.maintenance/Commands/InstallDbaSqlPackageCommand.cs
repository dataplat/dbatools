#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Downloads and installs the Microsoft SqlPackage utility used by the DACPAC commands. The
/// platform detection, download, extraction/MSI install, and ShouldProcess flow remain a
/// module-scoped PowerShell compatibility hop; this cmdlet supplies the real ShouldProcess
/// runtime. There is no SqlInstance surface - the command runs once against the local machine, so
/// the body is a single process-record hop with no cross-record carrier. Surface pinned by
/// migration/baselines/Install-DbaSqlPackage.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Install, "DbaSqlPackage", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InstallDbaSqlPackageCommand : DbaBaseCmdlet
{
    /// <summary>The custom directory path where SqlPackage will be extracted or installed.</summary>
    [Parameter(Position = 0)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Install for the current user only or system-wide for all users.</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    [ValidateSet("CurrentUser", "AllUsers")]
    public string Scope { get; set; } = "CurrentUser";

    /// <summary>The installation method - portable Zip or Windows Msi.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    [ValidateSet("Zip", "Msi")]
    public string Type { get; set; } = "Zip";

    /// <summary>Path to a pre-downloaded SqlPackage installation file (MSI or ZIP).</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? LocalFile { get; set; }

    /// <summary>Force a fresh download and reinstall even if SqlPackage already exists.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

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
            Path, Scope, Type, LocalFile, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string ProcessScript = """
param($Path, $Scope, $Type, $LocalFile, $Force, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([string]$Path, [string]$Scope, [string]$Type, [string]$LocalFile, $Force, $EnableException, $__realCmdlet)

    if ($Force) { $ConfirmPreference = 'none' }

    if ($LocalFile.StartsWith("http")) {
        Stop-Function -Message "LocalFile cannot be a URL. It must be a local file path." -FunctionName Install-DbaSqlPackage
        return
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Checking for existing installation..." -PercentComplete 0

    $installedPath = Get-DbaSqlPackagePath
    if ($installedPath -and -not $Force) {
        Write-Progress -Activity "Installing SqlPackage" -Completed
        $notes = "SqlPackage already exists at $installedPath. Skipped installation. Use -Force to overwrite."
        Write-Message -Level Verbose -Message $notes -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
        # Return the installation information
        [PSCustomObject]@{
            Name      = if ($PSVersionTable.Platform -eq "Unix") { "sqlpackage" } else { "SqlPackage.exe" }
            Path      = $installedPath
            Installed = $true
            Notes     = $notes
        }
        return
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Validating platform and permissions..." -PercentComplete 10

    # Platform-specific validations
    if ($PSVersionTable.Platform -eq "Unix") {
        # Unix platforms only support Zip type and CurrentUser scope
        if ($Type -eq "Msi") {
            Write-Progress -Activity "Installing SqlPackage" -Completed
            Stop-Function -Message "MSI installation is only supported on Windows. Use Zip type on Unix platforms." -FunctionName Install-DbaSqlPackage
            return
        }
        if ($Scope -eq "AllUsers") {
            Write-Progress -Activity "Installing SqlPackage" -Completed
            Stop-Function -Message "AllUsers scope is only supported on Windows. Use CurrentUser scope on Unix platforms." -FunctionName Install-DbaSqlPackage
            return
        }
    } else {
        # Windows-specific validations
        # Validate scope and type combination
        if ($Type -eq "Msi" -and $Scope -eq "CurrentUser") {
            Write-Progress -Activity "Installing SqlPackage" -Completed
            Stop-Function -Message "MSI installation is only supported for AllUsers scope. Use Zip type for CurrentUser scope." -FunctionName Install-DbaSqlPackage
            return
        }

        # Check for admin privileges when using MSI or AllUsers scope
        if ($Type -eq "Msi" -or $Scope -eq "AllUsers") {
            try {
                $null = Test-ElevationRequirement -ComputerName $env:COMPUTERNAME -Continue
            } catch {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "MSI installation and AllUsers scope require administrative privileges. Please run as administrator or use CurrentUser scope with Zip type." -FunctionName Install-DbaSqlPackage
                return
            }
        }
    }

    # Set default path based on scope and platform if not specified
    if (-not $Path) {
        if ($Scope -eq "CurrentUser") {
            # Install to dbatools data directory
            $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
            # Normalize path to remove any trailing slashes before joining
            $dbatoolsData = $dbatoolsData.TrimEnd('/', '\')
            $Path = Join-Path -Path $dbatoolsData -ChildPath "sqlpackage"
        } else {
            # AllUsers scope uses platform-specific default location
            if ($PSVersionTable.Platform -eq "Unix") {
                $Path = "/usr/local/sqlpackage"
            } else {
                $Path = "${env:ProgramFiles}\Microsoft SQL Server\DAC\bin"
            }
        }
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Determining download URLs..." -PercentComplete 5

    # Determine URLs based on type and platform
    if ($Type -eq "Zip") {
        if ($PSVersionTable.Platform -eq "Unix") {
            if ($IsLinux) {
                $url = "https://aka.ms/sqlpackage-linux"
            } elseif ($IsMacOS) {
                $url = "https://aka.ms/sqlpackage-macos"
            } else {
                $url = "https://aka.ms/sqlpackage-linux"  # Default to Linux for other Unix
            }
        } else {
            $url = "https://aka.ms/sqlpackage-windows"  # Windows .NET 8 ZIP (portable)
        }
        $fileName = "sqlpackage.zip"
    } else {
        $url = "https://aka.ms/dacfx-msi"  # Windows .NET Framework MSI
        $fileName = "dacfx.msi"
    }

    if (-not $LocalFile) {
        $temp = ([System.IO.Path]::GetTempPath())
        $LocalFile = Join-Path -Path $temp -ChildPath $fileName
    }

    $shouldInstall = $__realCmdlet.ShouldProcess("$LocalFile", "Install SqlPackage")

    # Download if needed
    if ($shouldInstall -and (-not (Test-Path -Path $LocalFile) -or $Force)) {
        try {
            Write-Progress -Activity "Installing SqlPackage" -Status "Starting download from Microsoft..." -PercentComplete 20
            Write-Message -Level Verbose -Message "Downloading SqlPackage from $url" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
            try {
                Invoke-TlsWebRequest -Uri $url -OutFile $LocalFile -UseBasicParsing -ErrorAction Stop
            } catch {
                Write-Message -Level Verbose -Message "Probably using a proxy for internet access, trying default proxy settings" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
                Write-Progress -Activity "Installing SqlPackage" -Status "Retrying download with proxy settings..." -PercentComplete 28
                (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                Invoke-TlsWebRequest -Uri $url -OutFile $LocalFile -UseBasicParsing -ErrorAction Stop
            }
            Write-Progress -Activity "Installing SqlPackage" -Status "Download completed successfully" -PercentComplete 45
        } catch {
            Write-Progress -Activity "Installing SqlPackage" -Completed
            Stop-Function -Message "Couldn't download SqlPackage. Download failed: $_" -ErrorRecord $_ -FunctionName Install-DbaSqlPackage
            return
        }
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Preparing installation..." -PercentComplete 50

    # Install SqlPackage
    if ($shouldInstall) {
        if (-not (Test-Path -Path $LocalFile)) {
            Write-Progress -Activity "Installing SqlPackage" -Completed
            Stop-Function -Message "LocalFile $LocalFile does not exist." -FunctionName Install-DbaSqlPackage
            return
        }

        if ($LocalFile.EndsWith(".msi") -or $Type -eq "Msi") {
            Write-Progress -Activity "Installing SqlPackage" -Status "Installing MSI package..." -PercentComplete 70
            Write-Message -Level Verbose -Message "Installing SqlPackage MSI for AllUsers scope" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"

            $msiArgs = @(
                "/i `"$LocalFile`""
                "/quiet"
                "/qn"
                "/norestart"
            )
            $msiArguments = $msiArgs -join " "
            Write-Message -Level Verbose -Message "Installing SqlPackage from $LocalFile" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
            $process = Start-Process -FilePath msiexec -ArgumentList $msiArguments -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "Failed to install SqlPackage from $LocalFile. Exit code: $($process.ExitCode)" -FunctionName Install-DbaSqlPackage
                return
            }
        } else {
            Write-Progress -Activity "Installing SqlPackage" -Status "Extracting ZIP archive..." -PercentComplete 70
            Write-Message -Level Verbose -Message "Extracting SqlPackage zip to $Path" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
            if (-not (Test-Path -Path $Path)) {
                $null = New-Item -ItemType Directory -Path $Path -Force
            }
            # Remove existing files if Force is specified
            if ($Force -and (Test-Path -Path $Path)) {
                Remove-Item -Path "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Unpack archive
            try {
                Expand-Archive -Path $LocalFile -DestinationPath $Path -Force:$Force

                # Make executable on Unix platforms
                if ($PSVersionTable.Platform -eq "Unix") {
                    $executablePath = Join-Path $Path "sqlpackage"
                    if (Test-Path $executablePath) {
                        try {
                            & chmod "+x" $executablePath 2>$null
                        } catch {
                            Write-Message -Level Warning -Message "Could not make sqlpackage executable. You may need to run 'chmod +x $executablePath' manually." -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
                        }
                    }
                }
            } catch {
                Write-Progress -Activity "Installing SqlPackage" -Completed
                Stop-Function -Message "Unable to extract SqlPackage to $Path. $_" -ErrorRecord $_ -FunctionName Install-DbaSqlPackage
                return
            }
        }
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Verifying installation..." -PercentComplete 90

    # Verify installation
    if ($PSVersionTable.Platform -eq "Unix") {
        $sqlPackagePaths = @(
            "$Path/sqlpackage"
        )
    } else {
        $sqlPackagePaths = @(
            "$Path\SqlPackage.exe"
            "${env:ProgramFiles}\Microsoft SQL Server\*\DAC\bin\SqlPackage.exe"
        )
    }

    $sqlPackageFound = $false
    $installedPath = $null
    foreach ($sqlPath in $sqlPackagePaths) {
        if (Test-Path -Path $sqlPath) {
            $sqlPackageFound = $true
            $installedPath = $sqlPath
            Write-Message -Level Verbose -Message "SqlPackage found at: $sqlPath" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
            break
        }
    }

    Write-Progress -Activity "Installing SqlPackage" -Status "Installation completed!" -PercentComplete 100
    Start-Sleep -Milliseconds 500
    Write-Progress -Activity "Installing SqlPackage" -Completed

    if ($sqlPackageFound) {
        Write-Message -Level Verbose -Message "SqlPackage installed successfully" -FunctionName Install-DbaSqlPackage -ModuleName "dbatools"
        # Return the installation information
        [PSCustomObject]@{
            Name      = if ($PSVersionTable.Platform -eq "Unix") { "sqlpackage" } else { "SqlPackage.exe" }
            Path      = $installedPath
            Installed = $true
        }
    } else {
        Stop-Function -Message "SqlPackage installation failed - SqlPackage.exe not found in expected locations" -FunctionName Install-DbaSqlPackage
    }
} $Path $Scope $Type $LocalFile $Force $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
