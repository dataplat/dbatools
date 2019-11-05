function Invoke-DbaDbccFreeCache {
    <#
    .SYNOPSIS
        Execution of Database Console Commands that clear Server level Memory caches

    .DESCRIPTION
        Allows execution of Database Console Commands that act at Server Level to clear Memory caches

        Allows execution of the following commands
            DBCC FREEPROCCACHE
            DBCC FREESESSIONCACHE
            DBCC FREESYSTEMCACHE

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
        DBCC Operation to Perform - Supports specific set of operations

    .PARAMETER InputValue
        Value used for Operation - meaning depends on Operation
        DBCC FREEPROCCACHE accepts
            a plan_handle of type varbinary(64)
            a sql_handle of type varbinary(64)
            or the name of a Resource Governor resource pool of type sysname
            If blank then clears all elements from the plan cache
        DBCC FREESYSTEMCACHE accepts
            'ALL' for ALL specifies all supported caches
            or name of a Resource Governor pool cache
        Not required for other values

    .PARAMETER NoInformationalMessages
        Suppresses all informational messages.

    .PARAMETER MarkInUseForRemoval
        Used when Operation = DBCC FREESYSTEMCACHE
        Asynchronously frees currently used entries from their respective caches after they become unused

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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