function Export-DbaDacPackage {
    <#
    .SYNOPSIS
        Creates DACPAC or BACPAC deployment packages from SQL Server databases using SqlPackage

    .DESCRIPTION
        Creates database deployment packages for version control, migrations, and schema distribution. Generates DACPAC files containing database schema definitions or BACPAC files that include both schema and data. This automates the SqlPackage utility so you don't have to remember complex command-line syntax or manage connection strings manually.

        Perfect for creating deployable packages from development databases, capturing schema snapshots for source control, or preparing migration artifacts for different environments. The function handles multiple databases in batch operations and provides flexible table filtering when you only need specific objects.

        Uses Microsoft DAC Services under the hood with automatic SqlPackage installation if needed. Note that extraction can fail with three-part references to external databases or complex cross-database dependencies.

        For help with the extract action parameters and properties, refer to https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-extract

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER Path
        Specifies the directory where DACPAC or BACPAC files will be saved. Defaults to the configured DbatoolsExport path.
        Use this when you want to organize exports in a specific location or when working with multiple databases that need consistent file placement.

    .PARAMETER FilePath
        Specifies the complete file path including filename for the export package. Overrides both Path and automatic file naming.
        Use this when you need a specific filename or when exporting a single database to a predetermined location.

    .PARAMETER Database
        Specifies which databases to export as DACPAC or BACPAC packages. Accepts multiple database names and supports wildcards.
        Use this to target specific databases instead of processing all user databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during export operations. Works with both Database and AllUserDatabases parameters.
        Use this to exclude system databases, maintenance databases, or any databases you don't want to package.

    .PARAMETER AllUserDatabases
        Exports packages for all user databases on the instance, automatically excluding system databases.
        Use this for bulk operations when you want to create deployment packages for every application database.

    .PARAMETER Type
        Specifies the package type to create: Dacpac (schema-only) or Bacpac (schema and data). Defaults to Dacpac.
        Use Dacpac for version control and schema deployments, or Bacpac when you need to include table data for migrations or testing.

    .PARAMETER Table
        Specifies which tables to include in the export package. Provide as schema.table format (e.g., 'dbo.Users', 'Sales.Orders').
        Use this when you only need specific tables rather than the entire database, such as for partial deployments or data subsets.

    .PARAMETER DacOption
        Configures advanced export settings using a DacExtractOptions or DacExportOptions object created by New-DbaDacOption.
        Use this to control extraction behavior like command timeouts, table data inclusion, or specific schema elements to include or exclude.

    .PARAMETER ExtendedParameters
        Passes additional command-line parameters directly to SqlPackage.exe for advanced scenarios (e.g., '/OverwriteFiles:true /Quiet:true').
        Use this when you need SqlPackage options not available through DacOption or when integrating with existing SqlPackage workflows.

    .PARAMETER ExtendedProperties
        Passes additional property settings directly to SqlPackage.exe for fine-tuned control over extraction behavior.
        Use this when you need to set specific SqlPackage properties that aren't exposed through the standard DacOption parameter.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Dacpac, Deployment
        Author: Richie lee (@richiebzzzt)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaDacPackage

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config -FilePath C:\SharePoint_Config.dacpac

        Exports the dacpac for SharePoint_Config on sql2016 to C:\SharePoint_Config.dacpac

    .EXAMPLE
        PS C:\> $options = New-DbaDacOption -Type Dacpac -Action Export
        PS C:\> $options.ExtractAllTableData = $true
        PS C:\> $options.CommandTimeout = 0
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database DB1 -DacOption $options

        Uses DacOption object to set the CommandTimeout to 0 then extracts the dacpac for DB1 on sql2016 to C:\Users\username\Documents\DbatoolsExport\sql2016-DB1-20201227140759-dacpackage.dacpac including all table data. As noted the generated filename will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.

    .EXAMPLE
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -AllUserDatabases -ExcludeDatabase "DBMaintenance","DBMonitoring" -Path "C:\temp"
        Exports dacpac packages for all USER databases, excluding "DBMaintenance" & "DBMonitoring", on sql2016 and saves them to C:\temp. The generated filename(s) will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.

    .EXAMPLE
        PS C:\> $moreparams = "/OverwriteFiles:$true /Quiet:$true"
        PS C:\> Export-DbaDacPackage -SqlInstance sql2016 -Database SharePoint_Config -Path C:\temp -ExtendedParameters $moreparams

        Using extended parameters to over-write the files and performs the extraction in quiet mode to C:\temp\sql2016-SharePoint_Config-20201227140759-dacpackage.dacpac. Uses command line instead of SMO behind the scenes. As noted the generated filename will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.
    #>
    [CmdletBinding(DefaultParameterSetName = 'SMO')]
    param
    (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllUserDatabases,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [parameter(ParameterSetName = 'SMO')]
        [Alias('ExtractOptions', 'ExportOptions', 'DacExtractOptions', 'DacExportOptions', 'Options', 'Option')]
        [object]$DacOption,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedParameters,
        [parameter(ParameterSetName = 'CMD')]
        [string]$ExtendedProperties,
        [ValidateSet('Dacpac', 'Bacpac')]
        [string]$Type = 'Dacpac',
        [parameter(ParameterSetName = 'SMO')]
        [string[]]$Table,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path

        # Check if sqlpackage is available
        $sqlPackagePath = Get-DbaSqlPackagePath
        if (-not $sqlPackagePath) {
            $installChoice = Read-Host "SqlPackage is required but not found. Would you like to install it now using Install-DbaSqlPackage? (Y/N)"
            if ($installChoice -match '^[Yy]') {
                try {
                    Install-DbaSqlPackage
                    Write-Message -Level Output -Message "SqlPackage installed successfully. Continuing with export..."
                    $sqlPackagePath = Get-DbaSqlPackagePath
                    if (-not $sqlPackagePath) {
                        Stop-Function -Message "Failed to locate SqlPackage after installation. Please verify the installation." -EnableException:$EnableException
                        return
                    }
                } catch {
                    Stop-Function -Message "Failed to install SqlPackage. Please install manually or use Install-DbaSqlPackage." -EnableException:$EnableException
                    return
                }
            } else {
                Stop-Function -Message "SqlPackage is required for this operation. Please install SqlPackage manually or use Install-DbaSqlPackage." -EnableException:$EnableException
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ((Test-Bound -Not -ParameterName Database) -and (Test-Bound -Not -ParameterName ExcludeDatabase) -and (Test-Bound -Not -ParameterName AllUserDatabases)) {
            Stop-Function -Message "You must specify databases to execute against using either -Database, -ExcludeDatabase or -AllUserDatabases"
            return
        }

        #check that at least one of the DB selection parameters was specified
        if (!$AllUserDatabases -and !$Database) {
            Stop-Function -Message "Either -Database or -AllUserDatabases should be specified" -Continue
        }
        #Check Option object types - should have a specific type
        if ($Type -eq 'Dacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExtractOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExtractOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        } elseif ($Type -eq 'Bacpac') {
            if ($DacOption -and $DacOption -isnot [Microsoft.SqlServer.Dac.DacExportOptions]) {
                Stop-Function -Message "Microsoft.SqlServer.Dac.DacExportOptions object type is expected - got $($DacOption.GetType())."
                return
            }
        }

        #Create a tuple to be used as a table filter
        if ($Table) {
            $tblList = New-Object 'System.Collections.Generic.List[Tuple[String, String]]'
            foreach ($tableItem in $Table) {
                $tableSplit = $tableItem.Split('.')
                if ($tableSplit.Count -gt 1) {
                    $tblName = $tableSplit[-1]
                    $schemaName = $tableSplit[-2]
                } else {
                    $tblName = [string]$tableSplit
                    $schemaName = 'dbo'
                }
                $tblList.Add((New-Object "tuple[String, String]" -ArgumentList $schemaName, $tblName))
            }
        } else {
            $tblList = $null
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($Database) {
                $dbs = Get-DbaDatabase -SqlInstance $server -OnlyAccessible -Database $Database -ExcludeDatabase $ExcludeDatabase
            } else {
                # all user databases by default
                $dbs = Get-DbaDatabase -SqlInstance $server -OnlyAccessible -ExcludeSystem -ExcludeDatabase $ExcludeDatabase
            }
            if (-not $dbs) {
                Stop-Function -Message "Databases not found on $instance"-Target $instance -Continue
            }

            foreach ($db in $dbs) {
                $resultstime = [diagnostics.stopwatch]::StartNew()
                $dbName = $db.name
                $connstring = $server.ConnectionContext.ConnectionString | Convert-ConnectionString
                if ($connstring -notmatch 'Database=') {
                    $connstring = "$connstring;Database=$dbName"
                }

                Write-Message -Level Verbose -Message "Using connection string $connstring"

                if ($Type -eq 'Dacpac') {
                    $ext = 'dacpac'
                } elseif ($Type -eq 'Bacpac') {
                    $ext = 'bacpac'
                }

                $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type $ext -ServerName $instance -DatabaseName $dbName

                #using SMO by default
                if ($PsCmdlet.ParameterSetName -eq 'SMO') {
                    try {
                        $dacSvc = New-Object -TypeName Microsoft.SqlServer.Dac.DacServices -ArgumentList $connstring -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Could not connect to the connection string $connstring"-Target $instance -Continue
                    }
                    if (-not $DacOption) {
                        $opts = New-DbaDacOption -Type $Type -Action Export
                    } else {
                        $opts = $DacOption
                    }

                    $null = $output = Register-ObjectEvent -InputObject $dacSvc -EventName "Message" -SourceIdentifier "msg" -Action { $EventArgs.Message.Message }

                    if ($Type -eq 'Dacpac') {
                        Write-Message -Level Verbose -Message "Initiating Dacpac extract to $FilePath"
                        #not sure how to extract that info from the existing DAC application, leaving 1.0.0.0 for now
                        $version = New-Object System.Version -ArgumentList '1.0.0.0'
                        try {
                            $dacSvc.Extract($FilePath, $dbName, $dbName, $version, $null, $tblList, $opts, $null)
                        } catch {
                            Stop-Function -Message "DacServices extraction failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    } elseif ($Type -eq 'Bacpac') {
                        Write-Message -Level Verbose -Message "Initiating Bacpac export to $FilePath"
                        try {
                            $dacSvc.ExportBacpac($FilePath, $dbName, $opts, $tblList, $null)
                        } catch {
                            Stop-Function -Message "DacServices export failure" -ErrorRecord $_ -Continue
                        } finally {
                            Unregister-Event -SourceIdentifier "msg"
                        }
                    }
                    $finalResult = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                } elseif ($PsCmdlet.ParameterSetName -eq 'CMD') {
                    if ($Type -eq 'Dacpac') { $action = 'Extract' }
                    elseif ($Type -eq 'Bacpac') { $action = 'Export' }
                    $cmdConnString = $connstring.Replace('"', "'")

                    $sqlPackageArgs = "/action:$action /tf:""$FilePath"" /SourceConnectionString:""$cmdConnString"" $ExtendedParameters $ExtendedProperties"

                    try {
                        $startprocess = New-Object System.Diagnostics.ProcessStartInfo

                        $sqlpackage = Get-DbaSqlPackagePath
                        if ($sqlpackage) {
                            $startprocess.FileName = $sqlpackage
                        } else {
                            Stop-Function -Message "SqlPackage not found. Please install SqlPackage using Install-DbaSqlPackage or ensure it's available in PATH." -Continue
                        }
                        $startprocess.Arguments = $sqlPackageArgs
                        $startprocess.RedirectStandardError = $true
                        $startprocess.RedirectStandardOutput = $true
                        $startprocess.UseShellExecute = $false
                        $startprocess.CreateNoWindow = $true
                        $process = New-Object System.Diagnostics.Process
                        $process.StartInfo = $startprocess
                        $process.Start() | Out-Null
                        $stdout = $process.StandardOutput.ReadToEnd()
                        $stderr = $process.StandardError.ReadToEnd()
                        $process.WaitForExit()
                        Write-Message -level Verbose -Message "StandardOutput: $stdout"
                        $finalResult = $stdout
                    } catch {
                        Stop-Function -Message "SQLPackage Failure" -ErrorRecord $_ -Continue
                    }

                    if ($process.ExitCode -ne 0) {
                        Stop-Function -Message "Standard output - $stderr"-Continue
                    }
                }
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Database     = $dbName
                    Path         = $FilePath
                    Elapsed      = [prettytimespan]($resultstime.Elapsed)
                    Result       = $finalResult
                } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
            }
        }
    }
}