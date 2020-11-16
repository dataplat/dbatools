function Export-DbaScript {
    <#
    .SYNOPSIS
        Exports scripts from SQL Management Objects (SMO)

    .DESCRIPTION
        Exports scripts from SQL Management Objects

    .PARAMETER InputObject
        A SQL Management Object such as the one returned from Get-DbaLogin

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.
        Will default to Path.DbatoolsExport Configuration entry

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER Encoding
        Specifies the file encoding. The default is UTF8.

        Valid values are:
        -- ASCII: Uses the encoding for the ASCII (7-bit) character set.
        -- BigEndianUnicode: Encodes in UTF-16 format using the big-endian byte order.
        -- Byte: Encodes a set of characters into a sequence of bytes.
        -- String: Uses the encoding type for a string.
        -- Unicode: Encodes in UTF-16 format using the little-endian byte order.
        -- UTF7: Encodes in UTF-7 format.
        -- UTF8: Encodes in UTF-8 format.
        -- Unknown: The encoding type is unknown or invalid. The data can be treated as binary.

    .PARAMETER Passthru
        Output script to console

    .PARAMETER ScriptingOptionsObject
        An SMO Scripting Object that can be used to customize the output - see New-DbaScriptingOption
        Options set in the ScriptingOptionsObject may override other parameter values

    .PARAMETER BatchSeparator
        Specifies the Batch Separator to use. Uses the value from configuration Formatting.BatchSeparator by default. This is normally "GO"

    .PARAMETER NoPrefix
        Do not include a Prefix

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed

    .PARAMETER NoClobber
        Do not overwrite file

    .PARAMETER Append
        Append to file

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
        if ($IsWindows -ne $false) {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        } else { $executingUser = $env:USER }
        $commandName = $MyInvocation.MyCommand.Name
        $prefixArray = @()

        # If -Append or -Append:$true is passed in then set these variables. Otherwise, the caller has specified -Append:$false or not specified -Append and they want to overwrite the file if it already exists.
        $appendToScript = $false
        if ($Append) {
            $appendToScript = $true

            if ($ScriptingOptionsObject) {
                $ScriptingOptionsObject.AppendToFile = $true
            }
        }

        if ($ScriptingOptionsObject) {
            # Check if BatchTerminator is consistent
            if (($($ScriptingOptionsObject.ScriptBatchTerminator)) -and ([string]::IsNullOrWhitespace($BatchSeparator))) {
                Write-Message -Level Warning -Message "Setting ScriptBatchTerminator to true and also having BatchSeperarator as an empty or null string may produce unintended results."
            }
        }
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
                    $soAppendToFile = $ScriptingOptionsObject.AppendToFile
                    $soToFileOnly = $ScriptingOptionsObject.ToFileOnly
                    $soFileName = $ScriptingOptionsObject.FileName
                }

                if (-not $passthru) {
                    $scriptPath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $serverName
                } else {
                    $scriptPath = 'Console'
                }

                if ($NoPrefix) {
                    $prefix = $null
                } else {
                    $prefix = "/*`n`tCreated by $executingUser using dbatools $commandName for objects on $serverName at $(Get-Date)`n`tSee https://dbatools.io/$commandName for more information`n*/"
                }

                if ($passthru) {
                    if ($null -ne $prefix) {
                        $prefix | Out-String
                    }
                } else {
                    if ($prefixArray -notcontains $scriptPath) {
                        if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                            Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue
                        }
                        #Only at the first output we use the passed variables Append & NoClobber. For this execution the next ones need to use -Append
                        if ($null -ne $prefix) {
                            $prefix | Out-File -FilePath $scriptPath -Encoding $encoding -Append:$appendToScript -NoClobber:$NoClobber
                            $prefixArray += $scriptPath
                            Write-Message -Level Verbose -Message "Writing prefix to file $scriptPath"
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($env:computername, "Exporting $object from $server to $scriptPath")) {
                    Write-Message -Level Verbose -Message "Exporting $object"

                    if ($passthru) {
                        if ($ScriptingOptionsObject) {
                            $ScriptingOptionsObject.FileName = $null
                            foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($scriptBatchTerminator) {
                                    $scriptpart = "$scriptpart`r`n$BatchSeparator`r`n"
                                }
                                $scriptpart | Out-String
                            }
                        } else {
                            foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($BatchSeparator) {
                                    $scriptpart = "$scriptpart`r`n$BatchSeparator`r`n"
                                } else {
                                    $scriptpart = "$scriptpart`r`n"
                                }
                                $scriptpart | Out-String
                            }
                        }
                    } else {
                        if ($ScriptingOptionsObject) {
                            if ($scriptBatchTerminator) {
                                # Option to script batch terminator via ScriptingOptionsObject needs to write to file only
                                $ScriptingOptionsObject.AppendToFile = (($null -ne $prefix) -or $appendToScript )
                                $ScriptingOptionsObject.ToFileOnly = $true
                                if (-not  $ScriptingOptionsObject.FileName) {
                                    $ScriptingOptionsObject.FileName = $scriptPath
                                }
                                $null = $object.Script($ScriptingOptionsObject)
                                # Reset the changed values of the $ScriptingOptionsObject in case it is reused later
                                $ScriptingOptionsObject.AppendToFile = $soAppendToFile
                                $ScriptingOptionsObject.ToFileOnly = $soToFileOnly
                                $ScriptingOptionsObject.FileName = $soFileName
                            } else {
                                $ScriptingOptionsObject.FileName = $null
                                $scriptInFull = foreach ($scriptpart in $scripter.EnumScript($object)) {
                                    if ($BatchSeparator) {
                                        $scriptpart = "$scriptpart`r`n$BatchSeparator`r`n"
                                    } else {
                                        $scriptpart = "$scriptpart`r`n"
                                    }
                                    $scriptpart
                                }
                                $scriptInFull | Out-File -FilePath $scriptPath -Encoding $encoding -Append
                                $ScriptingOptionsObject.FileName = $soFileName
                            }
                        } else {
                            $scriptInFull = foreach ($scriptpart in $scripter.EnumScript($object)) {
                                if ($BatchSeparator) {
                                    $scriptpart = "$scriptpart`r`n$BatchSeparator`r`n"
                                } else {
                                    $scriptpart = "$scriptpart`r`n"
                                }
                                $scriptpart
                            }
                            $scriptInFull | Out-File -FilePath $scriptPath -Encoding $encoding -Append
                        }
                    }

                    if (-not $passthru) {
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
            }
        }
    }
}