function Install-DbaWhoIsActive {
    <#
    .SYNOPSIS
        Downloads and installs sp_WhoIsActive stored procedure for real-time SQL Server session monitoring

    .DESCRIPTION
        Installs Adam Machanic's sp_WhoIsActive stored procedure, the most widely-used tool for monitoring active SQL Server sessions in real-time. This procedure provides detailed information about currently running queries, blocking chains, wait statistics, and resource consumption without the overhead of SQL Server Profiler.

        The function automatically downloads the latest version from GitHub or uses a local file you specify. It handles installation to any database you choose, though master is recommended for server-wide availability. When sp_WhoIsActive already exists, the function performs an update instead.

        This eliminates the manual process of downloading, extracting, and deploying the procedure across multiple SQL Server instances. Essential for DBAs who need to quickly troubleshoot performance issues, identify blocking sessions, or monitor query execution in production environments.

        For more information about sp_WhoIsActive, visit http://whoisactive.com and http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

        Please consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database where sp_WhoIsActive will be installed. Defaults to master database if not specified in interactive mode.
        Installing in master makes the procedure available server-wide, while installing in a user database limits access to that database only.
        When running unattended or in scripts, this parameter is mandatory to avoid interactive prompts.

    .PARAMETER LocalFile
        Specifies the path to a local copy of sp_WhoIsActive instead of downloading from GitHub. Accepts either the zip file or the extracted SQL script.
        Use this when your SQL Server instances don't have internet access, when you need to deploy a specific version, or when you have customized the procedure.
        If not specified, the function automatically downloads the latest version from the official GitHub repository.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Forces a fresh download of sp_WhoIsActive from GitHub, bypassing any locally cached version.
        Use this when you need to ensure you have the absolute latest version or when troubleshooting installation issues with cached files.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, WhoIsActive
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        http://whoisactive.com

    .LINK
        https://dbatools.io/Install-DbaWhoIsActive

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance where sp_WhoIsActive was installed or updated.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The database where sp_WhoIsActive was installed
        - Name: Always 'sp_WhoisActive', the name of the installed stored procedure
        - Version: The version of sp_WhoIsActive that was installed (extracted from the procedure source code)
        - Status: String indicating 'Installed' for new installations or 'Updated' if the procedure already existed

    .EXAMPLE
        PS C:\> Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master

        Downloads sp_WhoisActive from the internet and installs to sqlserver2014a's master database. Connects to SQL Server using Windows Authentication.

    .EXAMPLE
        PS C:\> Install-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $cred

        Pops up a dialog box asking which database on sqlserver2014a you want to install the procedure into. Connects to SQL Server using SQL Authentication.

    .EXAMPLE
        PS C:\> Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master -LocalFile c:\SQLAdmin\sp_WhoIsActive.sql

        Installs sp_WhoisActive to sqlserver2014a's master database from the local file sp_WhoIsActive.sql.
        You can download this file from https://github.com/amachanic/sp_whoisactive/blob/master/sp_WhoIsActive.sql

    .EXAMPLE
        PS C:\> Install-DbaWhoIsActive -SqlInstance sqlserver2014a -Database master -LocalFile c:\SQLAdmin\sp_whoisactive-12.00.zip

        Installs sp_WhoisActive to sqlserver2014a's master database from the local file sp_whoisactive-12.00.zip.
        You can download this file from https://github.com/amachanic/sp_whoisactive/releases

    .EXAMPLE
        PS C:\> $instances = Get-DbaRegServer sqlserver
        PS C:\> Install-DbaWhoIsActive -SqlInstance $instances -Database master

        Installs sp_WhoisActive to all servers within CMS
    #>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateScript( { Test-Path -Path $_ -PathType Leaf })]
        [string]$LocalFile,
        [object]$Database,
        [switch]$EnableException,
        [switch]$Force
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        # Do we need a new local cached version of the software?
        $dbatoolsData = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsData'
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child 'WhoIsActive'
        if ($Force -or $LocalFile -or -not (Test-Path -Path $localCachedCopy)) {
            if ($PSCmdlet.ShouldProcess('WhoIsActive', 'Update local cached copy of the software')) {
                try {
                    Save-DbaCommunitySoftware -Software WhoIsActive -LocalFile $LocalFile -EnableException
                } catch {
                    Stop-Function -Message 'Failed to update local cached copy' -ErrorRecord $_
                }
            }
        }

        if ($PSCmdlet.ShouldProcess($env:computername, "Reading SQL file into memory")) {
            $sqlfile = (Get-ChildItem -Path $localCachedCopy -Filter 'sp_WhoIsActive.sql').FullName
            if ($null -eq $sqlfile) {
                Write-Message -Level Verbose -Message "New filename sp_WhoIsActive.sql not found, using old filename who_is_active.sql."
                $sqlfile = (Get-ChildItem -Path $localCachedCopy -Filter 'who_is_active.sql').FullName
            }
            Write-Message -Level Verbose -Message "Using $sqlfile."

            $sql = [IO.File]::ReadAllText($sqlfile)
            $sql = $sql -replace 'USE master', ''
            $batches = $sql -split "GO\r\n"

            $matchString = 'Who Is Active? v'

            If ($sql -like "*$matchString*") {
                $posStart = $sql.IndexOf("$matchString")
                $PosEnd = $sql.IndexOf(")", $PosStart)
                $versionWhoIsActive = $sql.Substring($posStart + $matchString.Length, $posEnd - ($posStart + $matchString.Length) + 1).TrimEnd()
            } Else {
                $versionWhoIsActive = ''
            }
        }

        function Get-ExceptionMessages {
            param(
                [Parameter(Mandatory)]
                [System.Exception]$Exception
            )

            $messages = New-Object System.Collections.Generic.List[string]

            while ($Exception) {
                if ($Exception.Message -and
                    $messages[-1] -ne $Exception.Message) {
                    $messages.Add($Exception.Message)
                }

                # Special handling for SqlException
                if ($Exception -is [Microsoft.Data.SqlClient.SqlException]) {
                    foreach ($err in $Exception.Errors) {
                        if ($err.Message -and
                            $messages[-1] -ne $err.Message) {
                            $messages.Add("SQL $($err.Number): $($err.Message)")
                        }
                    }
                }

                $Exception = $Exception.InnerException
            }

            $messages
        }

    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (-not $Database) {
                if ($PSCmdlet.ShouldProcess($instance, "Prompting with GUI list of databases")) {
                    $Database = Show-DbaDbList -SqlInstance $server -Title "Install sp_WhoisActive" -Header "To deploy sp_WhoisActive, select a database or hit cancel to quit." -DefaultDb "master"

                    if (-not $Database) {
                        Stop-Function -Message "You must select a database to install the procedure." -Target $Database
                        return
                    }

                    if ($Database -ne 'master') {
                        Write-Message -Level Warning -Message "You have selected a database other than master. When you run Invoke-DbaWhoIsActive in the future, you must specify -Database $Database."
                    }
                }
            }
            if ($PSCmdlet.ShouldProcess($instance, "Installing sp_WhoisActive")) {
                try {
                    $ProcedureExists_Query = "SELECT COUNT(*) [proc_count] FROM sys.procedures WHERE is_ms_shipped = 0 AND name LIKE '%sp_WhoisActive%'"

                    if ($server.Databases[$Database]) {
                        $ProcedureExists = ($server.Query($ProcedureExists_Query, $Database)).proc_count
                        foreach ($batch in $batches) {
                            Write-Warning "Running batch of length $($batch.Length) characters. First 100 characters: $($batch.Substring(0, [Math]::Min(100, $batch.Length)))"
                            try {
                                $null = $server.databases[$Database].ExecuteNonQuery($batch)
                            } catch {
                                $messages = Get-ExceptionMessages -Exception $_.Exception
                                Write-Warning "We have $($messages.Count) messages from the exception, here are the unique ones:"
                                foreach ($msg in $messages) {
                                    Write-Warning $msg
                                }
                                if ($batch) {
                                    Write-Warning "Now running batch with Invoke-DbaQuery to get better error messages if it fails."
                                    try {
                                        $out = Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $batch -MessagesToOutput -EnableException
                                        Write-Warning "Batch succeeded with Invoke-DbaQuery. Output: $out"
                                    } catch {
                                        $messages = Get-ExceptionMessages -Exception $_.Exception
                                        Write-Warning "We have $($messages.Count) messages from the exception, here are the unique ones:"
                                        foreach ($msg in $messages) {
                                            Write-Warning $msg
                                        }
                                    }
                                    Write-Warning "Now running batch with Invoke-DbaQuery with no error handling."
                                    Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $batch -MessagesToOutput
                                }
                            }
                        }

                        if ($ProcedureExists -gt 0) {
                            $status = 'Updated'
                        } else {
                            $status = 'Installed'
                        }


                        [PSCustomObject]@{
                            ComputerName = $server.ComputerName
                            InstanceName = $server.ServiceName
                            SqlInstance  = $server.DomainInstanceName
                            Database     = $Database
                            Name         = 'sp_WhoisActive'
                            Version      = $versionWhoIsActive
                            Status       = $status
                        }
                    } else {
                        Stop-Function -Message "Failed to find database $Database on $instance or $Database is not writeable." -Continue -Target $instance
                    }

                } catch {
                    Stop-Function -Message "Failed to install stored procedure." -ErrorRecord $_ -Continue -Target $instance
                }

            }
        }
    }
}