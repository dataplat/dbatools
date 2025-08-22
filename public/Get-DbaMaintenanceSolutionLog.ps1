function Get-DbaMaintenanceSolutionLog {
    <#
    .SYNOPSIS
        Parses IndexOptimize text log files from Ola Hallengren's MaintenanceSolution when database logging is disabled.

    .DESCRIPTION
        Retrieves detailed execution information from IndexOptimize text log files when LogToTable='N' is configured in Ola Hallengren's MaintenanceSolution. This function parses the text files written to the SQL Server instance's log directory, extracting index operation details including start times, duration, fragmentation levels, and any errors encountered.

        This command specifically targets scenarios where database logging is disabled and only file-based logging is available. The parsed output includes granular details about each index operation, such as the specific ALTER INDEX commands executed, statistics updates, partition information, and operation outcomes.

        Be aware that this command only works if sqlcmd is used to execute the procedures, which is a legacy method not used by newer installations. Currently, only IndexOptimize log parsing is supported - DatabaseBackup and DatabaseIntegrityCheck parsing are not yet available.

        For modern deployments, we recommend using Install-DbaMaintenanceSolution and configuring procedures with LogToTable='Y' to enable database-based logging, which provides more reliable access to maintenance history.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogType
        Accepts 'IndexOptimize', 'DatabaseBackup', 'DatabaseIntegrityCheck'. Only IndexOptimize parsing is available at the moment

    .PARAMETER Since
        Consider only files generated since this date

    .PARAMETER Path
        Where to search for log files. By default it's the SQL instance error log path path

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, OlaHallengren
        Author: Klaas Vandenberghe (@powerdbaklaas) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        https://ola.hallengren.com

    .LINK
        https://dbatools.io/Get-DbaMaintenanceSolutionLog

    .EXAMPLE
        PS C:\> Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a

        Gets the outcome of the IndexOptimize job on sql instance sqlserver2014a.

    .EXAMPLE
        PS C:\> Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -SqlCredential $credential

        Gets the outcome of the IndexOptimize job on sqlserver2014a, using SQL Authentication.

    .EXAMPLE
        PS C:\> 'sqlserver2014a', 'sqlserver2020test' | Get-DbaMaintenanceSolutionLog

        Gets the outcome of the IndexOptimize job on sqlserver2014a and sqlserver2020test.

    .EXAMPLE
        PS C:\> Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -Path 'D:\logs\maintenancesolution\'

        Gets the outcome of the IndexOptimize job on sqlserver2014a, reading the log files in their custom location.

    .EXAMPLE
        PS C:\> Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -Since '2017-07-18'

        Gets the outcome of the IndexOptimize job on sqlserver2014a, starting from july 18, 2017.

    .EXAMPLE
        PS C:\> Get-DbaMaintenanceSolutionLog -SqlInstance sqlserver2014a -LogType IndexOptimize

        Gets the outcome of the IndexOptimize job on sqlserver2014a, the other options are not yet available! sorry

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('IndexOptimize', 'DatabaseBackup', 'DatabaseIntegrityCheck')]
        [string[]]$LogType = 'IndexOptimize',
        [datetime]$Since,
        [string]$Path,
        [switch]$EnableException
    )
    begin {
        function process-block ($block) {
            $fresh = @{
                'ObjectType'     = $null
                'IndexType'      = $null
                'ImageText'      = $null
                'NewLOB'         = $null
                'FileStream'     = $null
                'ColumnStore'    = $null
                'AllowPageLocks' = $null
                'PageCount'      = $null
                'Fragmentation'  = $null
                'Error'          = $null
            }
            foreach ($l in $block) {
                $splitted = $l -split ': ', 2
                if (($splitted.Length -ne 2) -or ($splitted[0].length -gt 20)) {
                    if ($null -eq $fresh['Error']) {
                        $fresh['Error'] = New-Object System.Collections.ArrayList
                    }
                    $null = $fresh['Error'].Add($l)
                    continue
                }
                $k = $splitted[0]
                $v = $splitted[1]
                if ($k -eq 'Date and Time') {
                    # this is the end date, we already parsed the start date of the block
                    if ($fresh.ContainsKey($k)) {
                        continue
                    }
                }
                $fresh[$k] = $v
            }
            if ($fresh.ContainsKey('Command')) {
                if ($fresh['Command'] -match '(SET LOCK_TIMEOUT (?<timeout>\d+); )?ALTER INDEX \[(?<index>[^\]]+)\] ON \[(?<database>[^\]]+)\]\.\[(?<schema>[^]]+)\]\.\[(?<table>[^\]]+)\] (?<action>[^\ ]+)( PARTITION = (?<partition>\d+))? WITH \((?<options>[^\)]+)') {
                    $fresh['Index'] = $Matches.index
                    $fresh['Statistics'] = $null
                    $fresh['Schema'] = $Matches.Schema
                    $fresh['Table'] = $Matches.Table
                    $fresh['Action'] = $Matches.action
                    $fresh['Options'] = $Matches.options
                    $fresh['Timeout'] = $Matches.timeout
                    $fresh['Partition'] = $Matches.partition
                } elseif ($fresh['Command'] -match '(SET LOCK_TIMEOUT (?<timeout>\d+); )?UPDATE STATISTICS \[(?<database>[^\]]+)\]\.\[(?<schema>[^]]+)\]\.\[(?<table>[^\]]+)\] \[(?<stat>[^\]]+)\]') {
                    $fresh['Index'] = $null
                    $fresh['Statistics'] = $Matches.stat
                    $fresh['Schema'] = $Matches.Schema
                    $fresh['Table'] = $Matches.Table
                    $fresh['Action'] = $null
                    $fresh['Options'] = $null
                    $fresh['Timeout'] = $Matches.timeout
                    $fresh['Partition'] = $null
                }
            }
            if ($fresh.ContainsKey('Comment')) {
                $commentParts = $fresh['Comment'] -split ', '
                foreach ($part in $commentParts) {
                    $indKey, $indValue = $part -split ': ', 2
                    if ($fresh.ContainsKey($indKey)) {
                        $fresh[$indKey] = $indValue
                    }
                }
            }
            if ($null -ne $fresh['Error']) {
                $fresh['Error'] = $fresh['Error'] -join "`n"
            }

            return $fresh
        }
    }
    process {
        foreach ($instance in $SqlInstance) {
            $logDir = $logFiles = $null
            $computername = $instance.ComputerName

            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }
            if ($LogType -ne 'IndexOptimize') {
                Write-Message -Level Warning -Message "Parsing $LogType is not supported at the moment"
                Continue
            }
            if (!$instance.IsLocalHost -and $server.HostPlatform -ne "Windows") {
                Write-Message -Level Warning -Message "The target instance is not Windows so logs cannot be fetched remotely"
                Continue
            }
            if ($Path) {
                $logDir = Join-AdminUnc -Servername $server.ComputerName -Filepath $Path
            } else {
                $logDir = Join-AdminUnc -Servername $server.ComputerName -Filepath $server.errorlogpath # -replace '^(.):', "\\$computername\`$1$"
            }
            if (!$logDir) {
                Write-Message -Level Warning -Message "No log directory returned from $instance"
                Continue
            }

            Write-Message -Level Verbose -Message "Log directory on $computername is $logDir"
            if (! (Test-Path $logDir)) {
                Write-Message -Level Warning -Message "Directory $logDir is not accessible"
                continue
            }
            $logFiles = [System.IO.Directory]::EnumerateFiles("$logDir", "IndexOptimize_*.txt")
            if ($Since) {
                $filteredLogs = @()
                foreach ($l in $logFiles) {
                    $base = $($l.Substring($l.Length - 15, 15))
                    try {
                        $dateFile = [DateTime]::ParseExact($base, 'yyyyMMdd_HHmmss', $null)
                    } catch {
                        $dateFile = Get-ItemProperty -Path $l | Select-Object -ExpandProperty CreationTime
                    }
                    if ($dateFile -gt $since) {
                        $filteredLogs += $l
                    }
                }
                $logFiles = $filteredLogs
            }
            if (! $logFiles.count -ge 1) {
                Write-Message -Level Warning -Message "No log files returned from $computername"
                Continue
            }
            $instanceInfo = @{ }
            $instanceInfo['ComputerName'] = $server.ComputerName
            $instanceInfo['InstanceName'] = $server.ServiceName
            $instanceInfo['SqlInstance'] = $server.Name

            foreach ($File in $logFiles) {
                Write-Message -Level Verbose -Message "Reading $file"
                $text = New-Object System.IO.StreamReader -ArgumentList "$File"
                $block = New-Object System.Collections.ArrayList
                $remember = @{ }
                while ($line = $text.ReadLine()) {

                    $real = $line.Trim()
                    if ($real.Length -eq 0) {
                        $processed = process-block $block
                        if ('Procedure' -in $processed.Keys) {
                            $block = New-Object System.Collections.ArrayList
                            continue
                        }
                        if ('Database' -in $processed.Keys) {
                            Write-Message -Level Verbose -Message "Index and Stats Optimizations on Database $($processed.Database) on $computername"
                            $processed.Remove('Is accessible')
                            $processed.Remove('User access')
                            $processed.Remove('Date and time')
                            $processed.Remove('Standby')
                            $processed.Remove('Recovery Model')
                            $processed.Remove('Updateability')
                            $processed['Database'] = $processed['Database'].Trim('[]')
                            $remember = $processed.Clone()
                        } else {
                            foreach ($k in $processed.Keys) {
                                $remember[$k] = $processed[$k]
                            }
                            $remember.Remove('Command')
                            $remember['StartTime'] = [dbadatetime]([DateTime]::ParseExact($remember['Date and time'] , "yyyy-MM-dd HH:mm:ss", $null))
                            $remember.Remove('Date and time')
                            $remember['Duration'] = ($remember['Duration'] -as [timespan])
                            [PSCustomObject]$remember
                        }
                        $block = New-Object System.Collections.ArrayList
                    } else {
                        $null = $block.Add($real)
                    }
                }
                $text.close()
            }
        }
    }
}