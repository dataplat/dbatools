function Export-DbaScript {
    <#
    .SYNOPSIS
        Generates T-SQL CREATE scripts from SQL Server Management Objects for migration and deployment

    .DESCRIPTION
        Takes any SQL Server Management Object from dbatools commands and converts it into executable T-SQL CREATE scripts using SMO scripting. This lets you script out database objects like tables, jobs, logins, stored procedures, and more for migration between environments or backup purposes. The function handles proper formatting with batch separators and supports custom scripting options to control what gets included in the output. Perfect for creating deployment scripts or documenting your SQL Server configurations without manual scripting.

    .PARAMETER InputObject
        Accepts any SQL Server Management Object (SMO) from dbatools commands like Get-DbaLogin, Get-DbaAgentJob, or Get-DbaDatabase.
        Use this when you need to generate CREATE scripts for specific database objects, jobs, logins, or other SQL Server components.
        The object type determines what kind of T-SQL script will be generated.

    .PARAMETER Path
        Sets the directory where script files will be saved when FilePath is not specified.
        Defaults to the configured dbatools export directory from your Path.DbatoolsExport setting.
        Use this when you want scripts saved to a standard location with auto-generated filenames.

    .PARAMETER FilePath
        Sets the complete file path and name for the output script file.
        Use this when you need the script saved to a specific location with a custom filename.
        Overrides the Path parameter when specified.

    .PARAMETER Encoding
        Controls the character encoding used when writing script files to disk.
        Default is UTF8 which handles international characters and is widely supported.
        Use UTF8 for most scenarios, or ASCII if you need compatibility with older tools that don't support Unicode.

    .PARAMETER Passthru
        Returns the generated T-SQL script as string output instead of writing to a file.
        Use this when you need to capture the script in a variable for further processing or modification.
        Commonly used in pipelines to transform scripts before saving.

    .PARAMETER ScriptingOptionsObject
        Accepts a customized SMO ScriptingOptions object created with New-DbaScriptingOption to control script generation.
        Use this when you need specific formatting like including schema context, headers, or data along with object definitions.
        Settings in this object override other Export-DbaScript parameters like BatchSeparator.

    .PARAMETER BatchSeparator
        Sets the batch terminator added between SQL statements in the output script.
        Defaults to "GO" from your dbatools configuration, which is standard for SQL Server Management Studio.
        Use a different separator if deploying to tools that require different batch terminators.

    .PARAMETER NoPrefix
        Suppresses the header comment block that normally identifies when and by whom the script was generated.
        Use this when you need clean scripts without metadata comments for automated deployments.
        The prefix normally includes timestamp, username, and dbatools version information.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER NoClobber
        Prevents overwriting existing files, causing the command to fail if the target file already exists.
        Use this as a safety measure when you want to ensure you don't accidentally replace existing scripts.
        Combine with -Append if you want to add to existing files instead.

    .PARAMETER Append
        Adds the generated script to the end of an existing file instead of overwriting it.
        Use this when building consolidated deployment scripts by combining multiple objects into one file.
        Particularly useful for scripting multiple databases or object types into a single migration script.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Backup, Export
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaScript

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript

        Exports all jobs on the SQL Server sql2016 instance using a trusted connection - automatically determines filename based on the Path.DbatoolsExport configuration setting, current time and server name.

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 | Export-DbaScript -FilePath C:\temp\export.sql -Append

        Exports all jobs on the SQL Server sql2016 instance using a trusted connection - Will append the output to the file C:\temp\export.sql if it already exists
        Inclusion of Batch Separator in script depends on the configuration s not include Batch Separator and will not compile

    .EXAMPLE
        PS C:\> Get-DbaDbTable -SqlInstance sql2016 -Database MyDatabase -Table 'dbo.Table1', 'dbo.Table2' -SqlCredential sqladmin | Export-DbaScript -FilePath C:\temp\export.sql

        Exports only script for 'dbo.Table1' and 'dbo.Table2' in MyDatabase to C:temp\export.sql and uses the SQL login "sqladmin" to login to sql2016

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 -Job syspolicy_purge_history, 'Hourly Log Backups' -SqlCredential sqladmin | Export-DbaScript -FilePath C:\temp\export.sql -NoPrefix

        Exports only syspolicy_purge_history and 'Hourly Log Backups' to C:temp\export.sql and uses the SQL login "sqladmin" to login to sql2016
        Suppress the output of a Prefix

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptSchema = $true
        PS C:\> $options.IncludeDatabaseContext  = $true
        PS C:\> $options.IncludeHeaders = $false
        PS C:\> $Options.NoCommandTerminator = $false
        PS C:\> $Options.ScriptBatchTerminator = $true
        PS C:\> $Options.AnsiFile = $true
        PS C:\> Get-DbaAgentJob -SqlInstance sql2016 -Job syspolicy_purge_history, 'Hourly Log Backups' -SqlCredential sqladmin | Export-DbaScript -FilePath C:\temp\export.sql -ScriptingOptionsObject $options

        Exports only syspolicy_purge_history and 'Hourly Log Backups' to C:temp\export.sql and uses the SQL login "sqladmin" to login to sql2016
        Uses Scripting options to ensure Batch Terminator is set

    .EXAMPLE
        PS C:\> Get-DbaAgentJob -SqlInstance sql2014 | Export-DbaScript -Passthru | ForEach-Object { $_.Replace('sql2014','sql2016') } | Set-Content -Path C:\temp\export.sql

        Exports jobs and replaces all instances of the servername "sql2014" with "sql2016" then writes to C:\temp\export.sql

    .EXAMPLE
        PS C:\> $options = New-DbaScriptingOption
        PS C:\> $options.ScriptSchema = $true
        PS C:\> $options.IncludeDatabaseContext  = $true
        PS C:\> $options.IncludeHeaders = $false
        PS C:\> $Options.NoCommandTerminator = $false
        PS C:\> $Options.ScriptBatchTerminator = $true
        PS C:\> $Options.AnsiFile = $true
        PS C:\> $Databases = Get-DbaDatabase -SqlInstance sql2016 -ExcludeDatabase master, model, msdb, tempdb
        PS C:\> foreach ($db in $Databases) {
        >>        Export-DbaScript -InputObject $db -FilePath C:\temp\export.sql -Append -Encoding UTF8 -ScriptingOptionsObject $options -NoPrefix
        >> }

        Exports Script for each database on sql2016 excluding system databases
        Uses Scripting options to ensure Batch Terminator is set
        Will append the output to the file C:\temp\export.sql if it already exists

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [Alias("ScriptingOptionObject")]
        [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet('ASCII', 'BigEndianUnicode', 'Byte', 'String', 'Unicode', 'UTF7', 'UTF8', 'Unknown')]
        [string]$Encoding = 'UTF8',
        [string]$BatchSeparator = (Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator'),
        [switch]$NoPrefix,
        [switch]$Passthru,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = $MyInvocation.MyCommand.Name
        $prefixArray = @()

        # If -Append or -Append:$true is passed in then set these variables. Otherwise, the caller has specified -Append:$false or not specified -Append and they want to overwrite the file if it already exists.
        $appendToScript = $false
        if ($Append) {
            $appendToScript = $true
        }

        if ($ScriptingOptionsObject) {
            # Check if BatchTerminator is consistent
            if (($($ScriptingOptionsObject.ScriptBatchTerminator)) -and ([string]::IsNullOrWhitespace($BatchSeparator))) {
                Write-Message -Level Warning -Message "Setting ScriptBatchTerminator to true and also having BatchSeperarator as an empty or null string may produce unintended results."
            }
            # Save those properties that will be changed in the process block so that they can be reset at the end
            $soAppendToFile = $ScriptingOptionsObject.AppendToFile
            $soToFileOnly = $ScriptingOptionsObject.ToFileOnly
            $soFileName = $ScriptingOptionsObject.FileName
        }

        $eol = [System.Environment]::NewLine
    }

    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($object in $InputObject) {

            $typename = $object.GetType().ToString()

            if ($typename.StartsWith('Microsoft.SqlServer.')) {
                $shorttype = $typename.Split(".")[-1]
            } else {
                Stop-Function -Message "InputObject is of type $typename which is not a SQL Management Object. Only SMO objects are supported." -Category InvalidData -Target $object -Continue
            }

            if ($shorttype -in "LinkedServer", "Credential", "Login") {
                Write-Message -Level Warning -Message "Support for $shorttype is limited at this time. No passwords, hashed or otherwise, will be exported if they exist."
            }

            # Just gotta add the stuff that Nic Cain added to his script

            if ($shorttype -eq "Configuration") {
                Write-Message -Level Warning -Message "Support for $shorttype is limited at this time."
            }

            if ($shorttype -eq "AvailabilityGroup") {
                Write-Message -Level Verbose -Message "Invoking .Script() as a workaround for https://github.com/dataplat/dbatools/issues/5913."
                try {
                    $null = $InputObject.Script()
                } catch {
                    Write-Message -Level Verbose -Message "Invoking .Script() failed: $_"
                }
            }

            # Find the server object to pass on to the function
            $parent = $object.parent

            do {
                if ($parent.Urn.Type -ne "Server") {
                    $parent = $parent.Parent
                }
            }
            until (($parent.Urn.Type -eq "Server") -or (-not $parent))

            if (-not $parent -and -not (Get-Member -InputObject $object -Name ScriptCreate) ) {
                Stop-Function -Message "Failed to find valid SMO server object in input: $object." -Category InvalidData -Target $object -Continue
            }

            try {
                $server = $parent
                $serverName = $server.Name.Replace('\', '$')

                $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter $server
                if ($ScriptingOptionsObject) {
                    $scripter.Options = $ScriptingOptionsObject
                    $scriptBatchTerminator = $ScriptingOptionsObject.ScriptBatchTerminator
                }

                if (-not $Passthru) {
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $serverName
                } else {
                    $scriptPath = 'Console'
                }

                if ($NoPrefix) {
                    $prefix = $null
                } else {
                    $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $serverName at $(Get-Date)$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
                }

                if ($Passthru) {
                    if ($null -ne $prefix) {
                        $prefix | Out-String
                    }
                } else {
                    if ($prefixArray -notcontains $scriptPath) {
                        if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                            Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue
                        }
                        #Only at the first output we use the passed variables Append & NoClobber. For this execution the next ones need to use -Append
                        # Empty $prefix will clean file in case $appendToScript is not set.
                        Write-Message -Level Verbose -Message "Writing (maybe empty) prefix to file $scriptPath"
                        $prefix | Out-File -FilePath $scriptPath -Encoding $encoding -Append:$appendToScript -NoClobber:$NoClobber
                        $prefixArray += $scriptPath
                    }
                }

                if ($Pscmdlet.ShouldProcess($env:computername, "Exporting $object from $server to $scriptPath")) {
                    Write-Message -Level Verbose -Message "Exporting $object"

                    if ($Passthru) {
                        if ($ScriptingOptionsObject) {
                            $ScriptingOptionsObject.FileName = $null
                            foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($scriptBatchTerminator) {
                                    $scriptpart = "$scriptpart$eol$BatchSeparator$eol"
                                }
                                $scriptpart | Out-String
                            }
                        } else {
                            foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($BatchSeparator) {
                                    $scriptpart = "$scriptpart$eol$BatchSeparator$eol"
                                } else {
                                    $scriptpart = "$scriptpart$eol"
                                }
                                $scriptpart | Out-String
                            }
                        }
                    } else {
                        if ($ScriptingOptionsObject) {
                            if ($scriptBatchTerminator) {
                                # Option to script batch terminator via ScriptingOptionsObject needs to write to file only
                                $ScriptingOptionsObject.AppendToFile = $true
                                $ScriptingOptionsObject.ToFileOnly = $true
                                if (-not $ScriptingOptionsObject.FileName) {
                                    $ScriptingOptionsObject.FileName = $scriptPath
                                }
                                $null = $object.Script($ScriptingOptionsObject)
                            } else {
                                $ScriptingOptionsObject.FileName = $null
                                $scriptInFull = foreach ($scriptpart in $scripter.EnumScript($object)) {
                                    if ($BatchSeparator) {
                                        $scriptpart = "$scriptpart$eol$BatchSeparator$eol"
                                    } else {
                                        $scriptpart = "$scriptpart$eol"
                                    }
                                    $scriptpart
                                }
                                $scriptInFull | Out-File -FilePath $scriptPath -Encoding $encoding -Append
                            }
                        } else {
                            $scriptInFull = foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($BatchSeparator) {
                                    $scriptpart = "$scriptpart$eol$BatchSeparator$eol"
                                } else {
                                    $scriptpart = "$scriptpart$eol"
                                }
                                $scriptpart
                            }
                            $scriptInFull | Out-File -FilePath $scriptPath -Encoding $encoding -Append
                        }
                    }

                    if (-not $Passthru) {
                        Write-Message -Level Verbose -Message "Exported $object on $($server.Name) to $scriptPath"
                        Get-ChildItem -Path $scriptPath
                    }
                }
            } catch {
                $message = $_.Exception.InnerException.InnerException.InnerException.Message
                if (-not $message) {
                    $message = $_.Exception
                }
                Stop-Function -Message "Failure on $($server.Name) | $message" -Target $server
            } finally {
                # Reset the changed values of the $ScriptingOptionsObject in case it is reused later
                if ($ScriptingOptionsObject) {
                    $ScriptingOptionsObject.AppendToFile = $soAppendToFile
                    $ScriptingOptionsObject.ToFileOnly = $soToFileOnly
                    $ScriptingOptionsObject.FileName = $soFileName
                }
            }
        }
    }
}