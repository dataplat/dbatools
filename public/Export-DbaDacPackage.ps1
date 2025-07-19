function Export-DbaDacPackage {
    <#
    .SYNOPSIS
        Exports a dacpac from a server.

    .DESCRIPTION
        Using SQLPackage, export a dacpac from an instance of SQL Server.

        This function now uses sqlpackage command-line tool by default when using New-DbaDacOption, providing better compatibility with newer SQL Server versions. Legacy DAC framework support is maintained for backward compatibility.

        Note - Extract from SQL Server is notoriously flaky - for example if you have three part references to external databases it will not work.

        For help with the extract action parameters and properties, refer to https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-extract

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Only SQL authentication is supported. When not specified, uses Trusted Authentication.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllUserDatabases
        Run command against all user databases

    .PARAMETER Type
        Selecting the type of the export: Dacpac (default) or Bacpac.

    .PARAMETER Table
        List of the tables to include into the export. Should be provided as an array of strings: dbo.Table1, Table2, Schema1.Table3.

    .PARAMETER DacOption
        Export options for a corresponding export type. Can be created by New-DbaDacOption -Type Dacpac | Bacpac
        When using New-DbaDacOption, creates sqlpackage-compatible options that work with newer SQL Server versions.
        Legacy Microsoft.SqlServer.Dac objects are still supported for backward compatibility.

    .PARAMETER ExtendedParameters
        Optional parameters used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

    .PARAMETER ExtendedProperties
        Optional properties used to extract the DACPAC. More information can be found at
        https://msdn.microsoft.com/en-us/library/hh550080.aspx

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

        Uses sqlpackage-compatible DacOption object to set the CommandTimeout to 0 then extracts the dacpac for DB1 on sql2016 to C:\Users\username\Documents\DbatoolsExport\sql2016-DB1-20201227140759-dacpackage.dacpac including all table data. As noted the generated filename will contain the server name, database name, and the current timestamp in the "%Y%m%d%H%M%S" format.

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
        #Check Option object types - should be our custom sqlpackage-compatible type or allow legacy objects
        if ($DacOption) {
            $validTypes = @(
                'DbaTools.sqlpackage.Options',
                'Microsoft.SqlServer.Dac.DacExtractOptions',
                'Microsoft.SqlServer.Dac.DacExportOptions'
            )

            $isValidType = $false
            foreach ($validType in $validTypes) {
                if ($DacOption.PSTypeNames -contains $validType -or $DacOption.GetType().FullName -eq $validType) {
                    $isValidType = $true
                    break
                }
            }

            if (-not $isValidType) {
                Stop-Function -Message "Expected sqlpackage-compatible options object or legacy DAC options object - got $($DacOption.GetType())."
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

                #using SMO by default, but fallback to sqlpackage for new options objects
                if ($PsCmdlet.ParameterSetName -eq 'SMO') {
                    if (-not $DacOption) {
                        $opts = New-DbaDacOption -Type $Type -Action Export
                    } else {
                        $opts = $DacOption
                    }

                    # Check if we have a new sqlpackage-compatible options object or legacy DAC object
                    $usesqlpackage = $opts.PSTypeNames -contains 'DbaTools.sqlpackage.Options'

                    if ($usesqlpackage) {
                        # Use sqlpackage command line for new options objects
                        Write-Message -Level Verbose -Message "Using sqlpackage command-line tool for $Type extraction"

                        if ($Type -eq 'Dacpac') { $action = 'Extract' }
                        elseif ($Type -eq 'Bacpac') { $action = 'Export' }

                        $cmdConnString = $connstring.Replace('"', "'")
                        $sqlPackageParams = $opts.TosqlpackageParameters()
                        $sqlPackageArgs = "/action:$action /tf:""$FilePath"" /SourceConnectionString:""$cmdConnString"" $sqlPackageParams"

                        try {
                            $startprocess = New-Object System.Diagnostics.ProcessStartInfo

                            $sqlpackage = (Get-Command sqlpackage -ErrorAction Ignore).Source
                            if ($sqlpackage) {
                                $startprocess.FileName = $sqlpackage
                            } else {
                                if ($IsLinux) {
                                    $startprocess.FileName = "$(Get-DbatoolsLibraryPath)/lib/dac/linux/sqlpackage"
                                } elseif ($IsMacOS) {
                                    $startprocess.FileName = "$(Get-DbatoolsLibraryPath)/lib/dac/mac/sqlpackage"
                                } else {
                                    $startprocess.FileName = Join-DbaPath -Path $(Get-DbatoolsLibraryPath) -ChildPath lib, dac, sqlpackage.exe
                                }
                            }

                            # Ensure working directory exists
                            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($FilePath)) | Out-Null
                            $startprocess.WorkingDirectory = [System.IO.Path]::GetDirectoryName($FilePath)
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
                            Stop-Function -Message "sqlpackage error - $stderr" -Continue
                        }
                    } else {
                        # Use legacy DAC services for backward compatibility
                        Write-Message -Level Verbose -Message "Using legacy DAC services for $Type extraction"

                        try {
                            $dacSvc = New-Object -TypeName Microsoft.SqlServer.Dac.DacServices -ArgumentList $connstring -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Could not connect to the connection string $connstring. Consider using sqlpackage-compatible options with New-DbaDacOption." -Target $instance -Continue
                        }

                        $null = $output = Register-ObjectEvent -InputObject $dacSvc -EventName "Message" -SourceIdentifier "msg" -Action { $EventArgs.Message.Message }

                        if ($Type -eq 'Dacpac') {
                            Write-Message -Level Verbose -Message "Initiating Dacpac extract to $FilePath"
                            #not sure how to extract that info from the existing DAC application, leaving 1.0.0.0 for now
                            $version = New-Object System.Version -ArgumentList '1.0.0.0'
                            try {
                                $dacSvc.Extract($FilePath, $dbName, $dbName, $version, $null, $tblList, $opts, $null)
                            } catch {
                                Stop-Function -Message "DacServices extraction failure. Consider using sqlpackage-compatible options with New-DbaDacOption." -ErrorRecord $_ -Continue
                            } finally {
                                Unregister-Event -SourceIdentifier "msg"
                            }
                        } elseif ($Type -eq 'Bacpac') {
                            Write-Message -Level Verbose -Message "Initiating Bacpac export to $FilePath"
                            try {
                                $dacSvc.ExportBacpac($FilePath, $dbName, $opts, $tblList, $null)
                            } catch {
                                Stop-Function -Message "DacServices export failure. Consider using sqlpackage-compatible options with New-DbaDacOption." -ErrorRecord $_ -Continue
                            } finally {
                                Unregister-Event -SourceIdentifier "msg"
                            }
                        }
                        $finalResult = ($output.output -join [System.Environment]::NewLine | Out-String).Trim()
                    }
                } elseif ($PsCmdlet.ParameterSetName -eq 'CMD') {
                    if ($Type -eq 'Dacpac') { $action = 'Extract' }
                    elseif ($Type -eq 'Bacpac') { $action = 'Export' }
                    $cmdConnString = $connstring.Replace('"', "'")

                    $sqlPackageArgs = "/action:$action /tf:""$FilePath"" /SourceConnectionString:""$cmdConnString"" $ExtendedParameters $ExtendedProperties"

                    try {
                        $startprocess = New-Object System.Diagnostics.ProcessStartInfo

                        $sqlpackage = (Get-Command sqlpackage -ErrorAction Ignore).Source
                        if ($sqlpackage) {
                            $startprocess.FileName = $sqlpackage
                        } else {
                            if ($IsLinux) {
                                $startprocess.FileName = "$(Get-DbatoolsLibraryPath)/lib/sqlpackage"
                            } elseif ($IsMacOS) {
                                $startprocess.FileName = "$(Get-DbatoolsLibraryPath)/lib/dac/mac/sqlpackage"
                            } else {
                                if ($PSVersionTable.PSEdition -eq 'Core') {
                                    $parentpath = Split-Path (Get-DbatoolsLibraryPath)
                                    $startprocess.FileName = Join-DbaPath -Path $parentpath -ChildPath desktop, lib, dac, sqlpackage.exe
                                } else {
                                    $startprocess.FileName = Join-DbaPath -Path $(Get-DbatoolsLibraryPath) -ChildPath lib, dac, sqlpackage.exe
                                }
                            }
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