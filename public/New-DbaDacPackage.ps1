function New-DbaDacPackage {
    <#
    .SYNOPSIS
        Creates a DACPAC package from SQL source files using the DacFx framework

    .DESCRIPTION
        Creates a DACPAC (Data-tier Application Package) from SQL source files without requiring MSBuild, Visual Studio, or the .NET SDK. Uses the Microsoft.SqlServer.Dac.Model.TSqlModel API to parse SQL files, validate the model, and generate a deployable DACPAC package.

        This command enables a pure PowerShell-based build workflow for database projects, making it ideal for CI/CD pipelines, development environments without Visual Studio, and cross-platform scenarios (Windows, Linux, macOS).

        The DACPAC output can be deployed using Publish-DbaDacPackage, enabling idempotent schema deployments with automatic dependency ordering and drift detection.

    .PARAMETER Path
        Specifies the directory containing SQL files to include in the DACPAC. All .sql files in the directory will be processed. Use -Recursive to include subdirectories.
        Alternatively, specify a path to a .sqlproj file to parse project settings and file references from the project definition.

    .PARAMETER OutputPath
        Specifies the output path for the generated DACPAC file. Defaults to a file named after the DatabaseName in the current directory with .dacpac extension.
        Example: If DatabaseName is "MyDatabase", the default output would be ".\MyDatabase.dacpac"

    .PARAMETER DacVersion
        Specifies the version number for the DACPAC package metadata. Defaults to "1.0.0.0".
        Use semantic versioning aligned with your build or release process.

    .PARAMETER DacDescription
        Specifies an optional description to embed in the DACPAC package metadata.
        Use this to document the package purpose or build context.

    .PARAMETER DatabaseName
        Specifies the database name for the DACPAC package metadata. Defaults to the name of the Path directory or current directory.
        This name is used when deploying the DACPAC if no target database name is specified.

    .PARAMETER Recursive
        Includes SQL files from subdirectories when Path is a directory.
        Use this to process hierarchical folder structures like Schema\Tables\, Schema\Views\, etc.

    .PARAMETER SqlServerVersion
        Specifies the target SQL Server version for model validation and compatibility checking.
        Valid values: Sql90 (2005), Sql100 (2008), Sql110 (2012), Sql120 (2014), Sql130 (2016), Sql140 (2017), Sql150 (2019), Sql160 (2022), SqlAzure.
        Defaults to Sql160 (SQL Server 2022).

    .PARAMETER Filter
        Specifies a wildcard pattern to filter which SQL files to include. Defaults to "*.sql".
        Use this to include only specific file patterns like "*Table*.sql" or "Schema_*.sql".

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any operations that change state.

    .NOTES
        Tags: Dacpac, Deployment
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        This command requires the DacFx library (Microsoft.SqlServer.Dac) which is included with dbatools.library.

        Key differences from other DACPAC workflows:
        - Export-DbaDacPackage: Extracts DACPAC from an EXISTING database (requires SQL Server connection)
        - New-DbaDacPackage: Creates DACPAC from SQL SOURCE FILES (no SQL Server required)
        - Publish-DbaDacPackage: Deploys DACPAC to a database (requires SQL Server connection)

        .OUTPUTS
        PSCustomObject

        Returns one result object per DACPAC build operation.

        On successful build:
        - ComputerName: The local computer name where the DACPAC was built
        - Path: Full file path to the created DACPAC file
        - Database: The database name embedded in the DACPAC package metadata
        - DatabaseName: Database name (same as Database property)
        - Version: Version string in semantic version format (e.g., "1.0.0.0")
        - FileCount: Number of SQL files processed into the DACPAC
        - ObjectCount: Number of database objects in the compiled model
        - Duration: Elapsed time for the build operation (prettytimespan object, displays as human-readable duration)
        - Success: Boolean True indicating successful DACPAC creation
        - Errors: Array of error messages encountered (empty array on success)
        - Warnings: Array of warning messages from validation (empty array if no warnings)

        Default display properties (via Select-DefaultView):
        - Path: File path to the DACPAC
        - DatabaseName: Database name
        - Version: Package version
        - FileCount: SQL files processed
        - ObjectCount: Database objects compiled
        - Duration: Build time elapsed
        - Success: Build status

        On build failure (when validation errors prevent DACPAC creation):
        - DacpacPath: Null (DACPAC was not created)
        - DatabaseName: Database name
        - Version: Version string
        - FileCount: Number of files attempted
        - ObjectCount: Object count at time of failure
        - Duration: Elapsed time before failure
        - Success: Boolean False
        - Errors: Array of validation and processing errors preventing build
        - Warnings: Array of warnings encountered before failure

        All objects are returned as PSCustomObject with properties accessible via dot notation or Select-Object.
        The output is pipeline-compatible with Publish-DbaDacPackage for automated deployment workflows.
        .OUTPUTS
        PSCustomObject

        Returns one result object per DACPAC build operation.

        On successful build:
        - ComputerName: The local computer name where the DACPAC was built
        - Path: Full file path to the created DACPAC file
        - Database: The database name embedded in the DACPAC package metadata
        - DatabaseName: Database name (same as Database property)
        - Version: Version string in semantic version format (e.g., "1.0.0.0")
        - FileCount: Number of SQL files processed into the DACPAC
        - ObjectCount: Number of database objects in the compiled model
        - Duration: Elapsed time for the build operation (prettytimespan object, displays as human-readable duration)
        - Success: Boolean True indicating successful DACPAC creation
        - Errors: Array of error messages encountered (empty array on success)
        - Warnings: Array of warning messages from validation (empty array if no warnings)

        Default display properties (via Select-DefaultView):
        - Path: File path to the DACPAC
        - DatabaseName: Database name
        - Version: Package version
        - FileCount: SQL files processed
        - ObjectCount: Database objects compiled
        - Duration: Build time elapsed
        - Success: Build status

        On build failure (when validation errors prevent DACPAC creation):
        - DacpacPath: Null (DACPAC was not created)
        - DatabaseName: Database name
        - Version: Version string
        - FileCount: Number of files attempted
        - ObjectCount: Object count at time of failure
        - Duration: Elapsed time before failure
        - Success: Boolean False
        - Errors: Array of validation and processing errors preventing build
        - Warnings: Array of warnings encountered before failure

        All objects are returned as PSCustomObject with properties accessible via dot notation or Select-Object.
        The output is pipeline-compatible with Publish-DbaDacPackage for automated deployment workflows.
    .LINK
        https://dbatools.io/New-DbaDacPackage

    .EXAMPLE
        PS C:\> New-DbaDacPackage -Path C:\Projects\MyDatabase\Schema -OutputPath C:\Build\MyDatabase.dacpac

        Creates a DACPAC from all SQL files in C:\Projects\MyDatabase\Schema and saves it to C:\Build\MyDatabase.dacpac.

    .EXAMPLE
        PS C:\> New-DbaDacPackage -Path C:\Projects\MyDatabase\Schema -Recursive -DatabaseName "MyAppDB" -DacVersion "2.1.0.0"

        Creates a DACPAC from all SQL files in the Schema directory and subdirectories, setting the database name to "MyAppDB" and version to "2.1.0.0".

    .EXAMPLE
        PS C:\> New-DbaDacPackage -Path C:\Projects\MyDatabase -Recursive | Publish-DbaDacPackage -SqlInstance sql2019 -Database TestDeploy

        Creates a DACPAC from source files and immediately deploys it to the TestDeploy database on sql2019.

    .EXAMPLE
        PS C:\> New-DbaDacPackage -Path C:\Projects\MyDatabase\Schema -SqlServerVersion Sql140 -Recursive

        Creates a DACPAC targeting SQL Server 2017 compatibility, useful when deploying to older SQL Server versions.

    .EXAMPLE
        PS C:\> New-DbaDacPackage -Path C:\Projects\MyDatabase -Filter "*Table*.sql" -Recursive

        Creates a DACPAC including only SQL files with "Table" in their filename.

    .EXAMPLE
        PS C:\> $result = New-DbaDacPackage -Path .\sql\Schema -Recursive -DatabaseName "dbatoolspro" -DacVersion "1.0.0"
        PS C:\> $result | Format-List

        Creates a DACPAC and displays detailed results including object count, duration, and any errors or warnings.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$OutputPath,
        [version]$DacVersion = "1.0.0.0",
        [string]$DacDescription,
        [string]$DatabaseName,
        [switch]$Recursive,
        [ValidateSet("Sql90", "Sql100", "Sql110", "Sql120", "Sql130", "Sql140", "Sql150", "Sql160", "SqlAzure")]
        [string]$SqlServerVersion = "Sql160",
        [string]$Filter = "*.sql",
        [switch]$EnableException
    )

    begin {
        # The DacFx types are loaded by dbatools.library - verify they are available
        try {
            $null = [Microsoft.SqlServer.Dac.Model.TSqlModel]
            Write-Message -Level Verbose -Message "DacFx Model types are available from dbatools.library"
        } catch {
            Stop-Function -Message "DacFx Model types are not available. Ensure dbatools.library is properly loaded."
            return
        }

        # Resolve the full path
        $resolvedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue

        if (-not $resolvedPath) {
            Stop-Function -Message "Path not found: $Path"
            return
        }

        $resolvedPath = $resolvedPath.Path
    }

    process {
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
                Stop-Function -Message "Failed to enumerate SQL files in $resolvedPath" -ErrorRecord $_
                return
            }

            if (-not $sqlFiles -or $sqlFiles.Count -eq 0) {
                Stop-Function -Message "No SQL files found in $resolvedPath matching filter '$Filter'"
                return
            }

            Write-Message -Level Verbose -Message "Found $($sqlFiles.Count) SQL files in $resolvedPath"

            # Default database name from directory name
            if (-not $DatabaseName) {
                $DatabaseName = $pathItem.Name
            }
        } elseif ($pathItem.Extension -eq ".sqlproj") {
            # Path is a .sqlproj file - parse the project
            Stop-Function -Message "Parsing .sqlproj files is not yet implemented. Please specify a directory path containing SQL files."
            return
        } else {
            Stop-Function -Message "Path must be a directory containing SQL files or a .sqlproj file. Got: $($pathItem.FullName)"
            return
        }

        # Set default output path if not specified
        if (-not $OutputPath) {
            $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath "$DatabaseName.dacpac"
        }

        # Ensure output directory exists
        $outputDir = Split-Path -Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path -Path $outputDir)) {
            if ($PSCmdlet.ShouldProcess($outputDir, "Create output directory")) {
                try {
                    $null = New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Failed to create output directory: $outputDir" -ErrorRecord $_
                    return
                }
            }
        }

        # Map version string to SqlServerVersion enum
        $sqlVersionEnum = [Microsoft.SqlServer.Dac.Model.SqlServerVersion]::$SqlServerVersion

        Write-Message -Level Verbose -Message "Creating TSqlModel with target version: $SqlServerVersion"

        # Create TSqlModel - handle different DacFx versions
        try {
            # First try with TSqlModelOptions (newer DacFx versions)
            [Microsoft.SqlServer.Dac.Model.TSqlModelOptions]$modelOptions = New-Object Microsoft.SqlServer.Dac.Model.TSqlModelOptions
            try {
                $model = New-Object Microsoft.SqlServer.Dac.Model.TSqlModel -ArgumentList @($sqlVersionEnum, $modelOptions)
            } catch {
                # Fallback: try with $null for options (some DacFx versions require this)
                Write-Message -Level Verbose -Message "Retrying TSqlModel creation with null options"
                $model = New-Object Microsoft.SqlServer.Dac.Model.TSqlModel -ArgumentList @($sqlVersionEnum, $null)
            }
        } catch {
            Stop-Function -Message "Failed to create TSqlModel. Ensure DacFx is properly loaded." -ErrorRecord $_
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
            Write-Message -Level Verbose -Message "Processing file $fileCount of $($sqlFiles.Count): $($sqlFile.Name)"

            try {
                $sqlContent = Get-Content -Path $sqlFile.FullName -Raw -ErrorAction Stop

                if ([string]::IsNullOrWhiteSpace($sqlContent)) {
                    Write-Message -Level Warning -Message "Skipping empty file: $($sqlFile.FullName)"
                    continue
                }

                # Add the SQL script to the model
                $model.AddObjects($sqlContent)

            } catch {
                $errorMessage = "Error processing file $($sqlFile.FullName): $($_.Exception.Message)"
                $null = $buildErrors.Add($errorMessage)
                Write-Message -Level Warning -Message $errorMessage
            }
        }

        # Validate the model
        Write-Message -Level Verbose -Message "Validating model..."

        try {
            $validationMessages = $model.Validate()

            foreach ($msg in $validationMessages) {
                $msgText = "$($msg.MessageType): $($msg.Message)"

                if ($msg.MessageType -eq [Microsoft.SqlServer.Dac.Model.DacMessageType]::Error) {
                    $null = $buildErrors.Add($msgText)
                    Write-Message -Level Warning -Message $msgText
                } else {
                    $null = $buildWarnings.Add($msgText)
                    Write-Message -Level Verbose -Message $msgText
                }
            }
        } catch {
            $errorMessage = "Model validation failed: $($_.Exception.Message)"
            $null = $buildErrors.Add($errorMessage)
            Write-Message -Level Warning -Message $errorMessage
        }

        # Count objects in model
        try {
            $allObjects = $model.GetObjects([Microsoft.SqlServer.Dac.Model.DacQueryScopes]::UserDefined)
            $objectCount = ($allObjects | Measure-Object).Count
            Write-Message -Level Verbose -Message "Model contains $objectCount user-defined objects"
        } catch {
            Write-Message -Level Warning -Message "Could not count model objects: $($_.Exception.Message)"
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

            Stop-Function -Message "Build failed with $($buildErrors.Count) error(s). Use -Verbose for details."
            return $result
        }

        if ($PSCmdlet.ShouldProcess($OutputPath, "Create DACPAC from $fileCount SQL files")) {
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
                Write-Message -Level Verbose -Message "Creating DACPAC at $OutputPath"

                [Microsoft.SqlServer.Dac.DacPackageExtensions]::BuildPackage($OutputPath, $model, $packageMetadata, $packageOptions)

                Write-Message -Level Output -Message "Successfully created DACPAC: $OutputPath"

            } catch {
                $errorMessage = "Failed to create DACPAC: $($_.Exception.Message)"
                $null = $buildErrors.Add($errorMessage)
                Stop-Function -Message $errorMessage -ErrorRecord $_
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
}


