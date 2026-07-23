function Invoke-DbaDbccFreeCache {
    <#
    .SYNOPSIS
        Clears SQL Server memory caches using DBCC commands to resolve performance issues and free memory

    .DESCRIPTION
        Executes DBCC commands to clear various SQL Server memory caches when troubleshooting performance problems or freeing memory on resource-constrained systems. This function helps DBAs resolve issues like parameter sniffing, plan cache bloat, or memory pressure without restarting the SQL Server service.

        Supports three cache-clearing operations:
        - DBCC FREEPROCCACHE: Clears procedure cache (all plans or specific plan handles/resource pools)
        - DBCC FREESESSIONCACHE: Clears distributed query connection cache for linked servers
        - DBCC FREESYSTEMCACHE: Clears system caches like token cache and ring buffers

        Use FREEPROCCACHE to resolve parameter sniffing issues or when query plans become inefficient. Use FREESESSIONCACHE when experiencing linked server connection problems. Use FREESYSTEMCACHE to clear authentication tokens and other system-level cached data.

        Read more:
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-freeproccache-transact-sql
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-freesessioncache-transact-sql
            - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-freesystemcache-transact-sql

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operation
        Specifies which cache clearing operation to perform: FreeProcCache, FreeSessionCache, or FreeSystemCache.
        Use FreeProcCache to resolve parameter sniffing or clear inefficient query plans, FreeSessionCache to clear linked server connections, or FreeSystemCache to clear authentication tokens and system-level caches.

    .PARAMETER InputValue
        Specifies a target value to limit the cache clearing operation instead of clearing all cache entries.
        For FreeProcCache: provide a specific plan_handle (0x...), sql_handle (0x...), or Resource Governor pool name to clear only those entries. For FreeSystemCache: provide a Resource Governor pool name to clear only that pool's cache entries.
        When omitted, clears all entries for the specified operation which is the typical DBA use case.

    .PARAMETER NoInformationalMessages
        Suppresses informational messages returned by the DBCC commands.
        Use this in scripts or automated processes where you only want to capture errors and warnings.

    .PARAMETER MarkInUseForRemoval
        Marks currently active cache entries for removal once they become unused, rather than waiting for them to be released.
        Only applies to FreeSystemCache operations and helps ensure memory is freed more aggressively on systems under memory pressure.

    .PARAMETER WhatIf
        Shows what would happen if the cmdlet runs. The cmdlet is not run.

    .PARAMETER Confirm
        Prompts you for confirmation before running the cmdlet.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DBCC
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance processed, containing the DBCC command that was executed and the resulting output from the SQL Server cache clearing operation.

        Properties:
        - ComputerName: The computer name of the SQL Server instance where the cache was cleared
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - Operation: The cache clearing operation executed (FreeProcCache, FreeSessionCache, or FreeSystemCache)
        - Cmd: The complete DBCC command that was executed (e.g., "DBCC FREEPROCCACHE WITH NO_INFOMSGS")
        - Output: The informational messages or output returned by the DBCC command; $null if -NoInformationalMessages was specified

    .LINK
        https://dbatools.io/Invoke-DbaDbccFreeCache

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREEPROCCACHE

        Runs the command DBCC FREEPROCCACHE against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREESESSIONCACHE -NoInformationalMessages

        Runs the command DBCC FREESESSIONCACHE WITH NO_INFOMSGS against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREESYSTEMCACHE -NoInformationalMessages

        Runs the command DBCC FREESYSTEMCACHE WITH NO_INFOMSGS against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREEPROCCACHE -InputValue 0x060006001ECA270EC0215D05000000000000000000000000

        Remove a specific plan with plan_handle 0x060006001ECA270EC0215D05000000000000000000000000 from the cache via the command DBCC FREEPROCCACHE(0x060006001ECA270EC0215D05000000000000000000000000) against the instance SqlServer2017 using Windows Authentication

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREEPROCCACHE -InputValue default

        Runs the command DBCC FREEPROCCACHE('default') against the instance SqlServer2017 using Windows Authentication. This clears all cache entries associated with a resource pool 'default'.

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREESYSTEMCACHE -InputValue default

        Runs the command DBCC FREESYSTEMCACHE ('ALL', default) against the instance SqlServer2017 using Windows Authentication. This will clean all the caches with entries specific to the resource pool named "default".

    .EXAMPLE
        PS C:\> Invoke-DbaDbccFreeCache -SqlInstance SqlServer2017 -Operation FREESYSTEMCACHE -InputValue default -MarkInUseForRemoval

        Runs the command DBCC FREESYSTEMCACHE ('ALL', default) WITH MARK_IN_USE_FOR_REMOVAL against the instance SqlServer2017 using Windows Authentication. This will to release entries once the entries become unused for all the caches with entries specific to the resource pool named "default".

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet('FreeProcCache', 'FreeSessionCache', 'FreeSystemCache')]
        [string]$Operation = "FreeProcCache",
        [string]$InputValue,
        [switch]$NoInformationalMessages,
        [switch]$MarkInUseForRemoval,
        [switch]$EnableException
    )
    begin {

        if (Test-Bound -ParameterName Operation) {
            $Operation = $Operation.ToUpper()
        } else {
            Write-Message -Level Warning -Message "You must specify an operation "
            continue
        }

        $stringBuilder = New-Object System.Text.StringBuilder
        if ($Operation -eq 'FREESESSIONCACHE') {
            $null = $stringBuilder.Append("DBCC $Operation")
            if (Test-Bound -ParameterName NoInformationalMessages) {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            }
        }
        if ($Operation -eq 'FREEPROCCACHE') {
            if (Test-Bound -ParameterName InputValue) {
                if ($InputValue.StartsWith('0x')) {
                    $null = $stringBuilder.Append("DBCC $Operation($InputValue)")
                } else {
                    $null = $stringBuilder.Append("DBCC $Operation('$InputValue')")
                }
                if (Test-Bound -ParameterName NoInformationalMessages) {
                    $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
                }
            } else {
                $null = $stringBuilder.Append("DBCC $Operation")
                if (Test-Bound -ParameterName NoInformationalMessages) {
                    $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
                }
            }
        }
        if ($Operation -eq 'FREESYSTEMCACHE') {
            if (Test-Bound -ParameterName InputValue) {
                $null = $stringBuilder.Append("DBCC FREESYSTEMCACHE('ALL', $InputValue)")
            } else {
                $null = $stringBuilder.Append("DBCC FREESYSTEMCACHE('ALL')")
            }
            if (Test-Bound -ParameterName NoInformationalMessages) {
                if (Test-Bound -ParameterName MarkInUseForRemoval) {
                    $null = $stringBuilder.Append(" WITH NO_INFOMSGS, MARK_IN_USE_FOR_REMOVAL")
                } else {
                    $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
                }
            } elseif (Test-Bound -ParameterName MarkInUseForRemoval) {
                $null = $stringBuilder.Append(" WITH MARK_IN_USE_FOR_REMOVAL")
            }
        }
    }
    process {
        $query = $StringBuilder.ToString()

        foreach ($instance in $SqlInstance) {
            Write-Message -Message "Attempting Connection to $instance" -Level Verbose
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            try {
                if ($Pscmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                    Write-Message -Message "Query to run: $query" -Level Verbose
                    $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
            }
            if ($Pscmdlet.ShouldProcess("console", "Outputting object")) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    Operation    = $Operation
                    Cmd          = $query.ToString()
                    Output       = $results
                }
            }
        }
    }
}