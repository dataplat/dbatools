#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS bodies) - split per the repo 400-line file limit.
public sealed partial class NewDbaDacPackageCommand
{

    // PS: the begin block VERBATIM, dot-sourced so each guard's "Stop-Function; return" exits only
    // the body while the sentinel still emits. Edits: -FunctionName on the three calls. The sentinel
    // carries the resolved path and whether either guard set the interrupt.
    private const string BeginScript = """
param($Path, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        # The DacFx types are loaded by dbatools.library - verify they are available
        try {
            $null = [Microsoft.SqlServer.Dac.Model.TSqlModel]
            Write-Message -Level Verbose -Message "DacFx Model types are available from dbatools.library" -FunctionName New-DbaDacPackage -ModuleName "dbatools"
        } catch {
            Stop-Function -Message "DacFx Model types are not available. Ensure dbatools.library is properly loaded." -FunctionName New-DbaDacPackage
            return
        }

        # Resolve the full path
        $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue

        if (-not $resolvedPath) {
            Stop-Function -Message "Path not found: $Path" -FunctionName New-DbaDacPackage
            return
        }

        $resolvedPath = $resolvedPath.Path
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__rp = Get-Variable -Name resolvedPath -Scope 0 -ErrorAction Ignore
    @{ __newDbaDacPackageBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); ResolvedPathAssigned = [bool]$__rp; ResolvedPath = $(if ($__rp) { $__rp.Value }) } }
} $Path $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so every "Stop-Function; return" exits only the
    // body. Edits: the two $PSCmdlet gates route to $__realCmdlet and -FunctionName is stamped on
    // the 22 direct Stop-Function/Write-Message calls. $resolvedPath restores from the begin
    // sentinel; unset-vs-assigned is preserved so a begin that never reached the assignment leaves
    // it unset here too.
    private const string ProcessScript = """
param($Path, $OutputPath, $DacVersion, $DacDescription, $DatabaseName, $SqlServerVersion, $Filter, $Recursive, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([string]$Path, [string]$OutputPath, [version]$DacVersion, [string]$DacDescription, [string]$DatabaseName, [string]$SqlServerVersion, [string]$Filter, $Recursive, $EnableException, $__beginState, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the one value begin leaves for process
    if ($__beginState.ResolvedPathAssigned) { $resolvedPath = $__beginState.ResolvedPath }

    . {
        if (Test-FunctionInterrupt) { return }

        $resultsTime = [System.Diagnostics.Stopwatch]::StartNew()

        # Determine if path is a directory or .sqlproj file
        $pathItem = Get-Item -Path $resolvedPath

        if ($pathItem.PSIsContainer) {
            # Path is a directory - scan for SQL files
            $searchOption = if ($Recursive) { "AllDirectories" } else { "TopDirectoryOnly" }

            try {
                $sqlFiles = Get-ChildItem -Path $resolvedPath -Filter $Filter -File -Recurse:$Recursive -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failed to enumerate SQL files in $resolvedPath" -ErrorRecord $_ -FunctionName New-DbaDacPackage
                return
            }

            if (-not $sqlFiles -or $sqlFiles.Count -eq 0) {
                Stop-Function -Message "No SQL files found in $resolvedPath matching filter '$Filter'" -FunctionName New-DbaDacPackage
                return
            }

            Write-Message -Level Verbose -Message "Found $($sqlFiles.Count) SQL files in $resolvedPath" -FunctionName New-DbaDacPackage -ModuleName "dbatools"

            # Default database name from directory name
            if (-not $DatabaseName) {
                $DatabaseName = $pathItem.Name
            }
        } elseif ($pathItem.Extension -eq ".sqlproj") {
            # Path is a .sqlproj file - parse the project
            Stop-Function -Message "Parsing .sqlproj files is not yet implemented. Please specify a directory path containing SQL files." -FunctionName New-DbaDacPackage
            return
        } else {
            Stop-Function -Message "Path must be a directory containing SQL files or a .sqlproj file. Got: $($pathItem.FullName)" -FunctionName New-DbaDacPackage
            return
        }

        # Set default output path if not specified
        if (-not $OutputPath) {
            $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath "$DatabaseName.dacpac"
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -Path $outputDir)) {
            if ($__realCmdlet.ShouldProcess($outputDir, "Create output directory")) {
                try {
                    $null = New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failed to create output directory: $outputDir" -ErrorRecord $_ -FunctionName New-DbaDacPackage
                    return
                }
            }
        }

        # Map version string to SqlServerVersion enum
        $sqlVersionEnum = [Microsoft.SqlServer.Dac.Model.SqlServerVersion]::$SqlServerVersion

        Write-Message -Level Verbose -Message "Creating TSqlModel with target version: $SqlServerVersion" -FunctionName New-DbaDacPackage -ModuleName "dbatools"

        # Create TSqlModel - handle different DacFx versions
        try {
            # First try with TSqlModelOptions (newer DacFx versions)
            [Microsoft.SqlServer.Dac.Model.TSqlModelOptions]$modelOptions = New-Object Microsoft.SqlServer.Dac.Model.TSqlModelOptions
            try {
                $model = New-Object Microsoft.SqlServer.Dac.Model.TSqlModel -ArgumentList @($sqlVersionEnum, $modelOptions)
            } catch {
                # Fallback: try with $null for options (some DacFx versions require this)
                Write-Message -Level Verbose -Message "Retrying TSqlModel creation with null options" -FunctionName New-DbaDacPackage -ModuleName "dbatools"
                $model = New-Object Microsoft.SqlServer.Dac.Model.TSqlModel -ArgumentList @($sqlVersionEnum, $null)
            }
        } catch {
            Stop-Function -Message "Failed to create TSqlModel. Ensure DacFx is properly loaded." -ErrorRecord $_ -FunctionName New-DbaDacPackage
            return
        }

        # Track errors and warnings
        $buildErrors = New-Object System.Collections.ArrayList
        $buildWarnings = New-Object System.Collections.ArrayList
        $fileCount = 0
        $objectCount = 0

        # Add SQL files to model
        foreach ($sqlFile in $sqlFiles) {
            $fileCount++
            Write-Message -Level Verbose -Message "Processing file $fileCount of $($sqlFiles.Count): $($sqlFile.Name)" -FunctionName New-DbaDacPackage -ModuleName "dbatools"

            try {
                $sqlContent = Get-Content -Path $sqlFile.FullName -Raw -ErrorAction Stop

                if ([string]::IsNullOrWhiteSpace($sqlContent)) {
                    Write-Message -Level Warning -Message "Skipping empty file: $($sqlFile.FullName)" -FunctionName New-DbaDacPackage -ModuleName "dbatools"
                    continue
                }

                # Add the SQL script to the model
                $model.AddObjects($sqlContent)

            } catch {
                $errorMessage = "Error processing file $($sqlFile.FullName): $($_.Exception.Message)"
                $null = $buildErrors.Add($errorMessage)
                Write-Message -Level Warning -Message $errorMessage -FunctionName New-DbaDacPackage -ModuleName "dbatools"
            }
        }

        # Validate the model
        Write-Message -Level Verbose -Message "Validating model..." -FunctionName New-DbaDacPackage -ModuleName "dbatools"

        try {
            $validationMessages = $model.Validate()

            foreach ($msg in $validationMessages) {
                $msgText = "$($msg.MessageType): $($msg.Message)"

                # DacMessageType is in Microsoft.SqlServer.Dac namespace, not Microsoft.SqlServer.Dac.Model
                if ($msg.MessageType -eq [Microsoft.SqlServer.Dac.DacMessageType]::Error) {
                    $null = $buildErrors.Add($msgText)
                    Write-Message -Level Warning -Message $msgText -FunctionName New-DbaDacPackage -ModuleName "dbatools"
                } else {
                    $null = $buildWarnings.Add($msgText)
                    Write-Message -Level Verbose -Message $msgText -FunctionName New-DbaDacPackage -ModuleName "dbatools"
                }
            }
        } catch {
            $errorMessage = "Model validation failed: $($_.Exception.Message)"
            $null = $buildErrors.Add($errorMessage)
            Write-Message -Level Warning -Message $errorMessage -FunctionName New-DbaDacPackage -ModuleName "dbatools"
        }

        # Count objects in model
        try {
            $allObjects = $model.GetObjects([Microsoft.SqlServer.Dac.Model.DacQueryScopes]::UserDefined)
            $objectCount = ($allObjects | Measure-Object).Count
            Write-Message -Level Verbose -Message "Model contains $objectCount user-defined objects" -FunctionName New-DbaDacPackage -ModuleName "dbatools"
        } catch {
            Write-Message -Level Warning -Message "Could not count model objects: $($_.Exception.Message)" -FunctionName New-DbaDacPackage -ModuleName "dbatools"
        }

        # Build the DACPAC
        if ($buildErrors.Count -gt 0) {
            $resultsTime.Stop()

            # Return result with errors but don't build
            $result = [PSCustomObject]@{
                DacpacPath   = $null
                DatabaseName = $DatabaseName
                Version      = $DacVersion.ToString()
                FileCount    = $fileCount
                ObjectCount  = $objectCount
                Duration     = [prettytimespan]($resultsTime.Elapsed)
                Success      = $false
                Errors       = $buildErrors.ToArray()
                Warnings     = $buildWarnings.ToArray()
            }

            Stop-Function -Message "Build failed with $($buildErrors.Count) error(s). Use -Verbose for details." -FunctionName New-DbaDacPackage
            return $result
        }

        if ($__realCmdlet.ShouldProcess($OutputPath, "Create DACPAC from $fileCount SQL files")) {
            try {
                # Create package metadata
                $packageMetadata = New-Object Microsoft.SqlServer.Dac.PackageMetadata
                $packageMetadata.Name = $DatabaseName
                $packageMetadata.Version = $DacVersion

                if ($DacDescription) {
                    $packageMetadata.Description = $DacDescription
                }

                # Create package options
                $packageOptions = New-Object Microsoft.SqlServer.Dac.PackageOptions

                # Build the DACPAC
                Write-Message -Level Verbose -Message "Creating DACPAC at $OutputPath" -FunctionName New-DbaDacPackage -ModuleName "dbatools"

                [Microsoft.SqlServer.Dac.DacPackageExtensions]::BuildPackage($OutputPath, $model, $packageMetadata, $packageOptions)

                Write-Message -Level Output -Message "Successfully created DACPAC: $OutputPath" -FunctionName New-DbaDacPackage -ModuleName "dbatools"

            } catch {
                $errorMessage = "Failed to create DACPAC: $($_.Exception.Message)"
                $null = $buildErrors.Add($errorMessage)
                Stop-Function -Message $errorMessage -ErrorRecord $_ -FunctionName New-DbaDacPackage
                return
            }
        }

        $resultsTime.Stop()

        # Return result object (pipeline-friendly for Publish-DbaDacPackage)
        [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            Path         = $OutputPath
            Database     = $DatabaseName
            DatabaseName = $DatabaseName
            Version      = $DacVersion.ToString()
            FileCount    = $fileCount
            ObjectCount  = $objectCount
            Duration     = [prettytimespan]($resultsTime.Elapsed)
            Success      = $true
            Errors       = $buildErrors.ToArray()
            Warnings     = $buildWarnings.ToArray()
        } | Select-DefaultView -Property Path, DatabaseName, Version, FileCount, ObjectCount, Duration, Success
    }
} $Path $OutputPath $DacVersion $DacDescription $DatabaseName $SqlServerVersion $Filter $Recursive $EnableException $__beginState $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
