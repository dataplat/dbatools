function Stop-DbaProcess {
    <#
    .SYNOPSIS
        Terminates SQL Server processes (SPIDs) to resolve blocking, kill runaway queries, or clean up connections.

    .DESCRIPTION
        Terminates SQL Server processes by targeting specific SPIDs, logins, hostnames, programs, or databases. This is essential for resolving blocking situations, stopping runaway queries that consume resources, or cleaning up abandoned connections from applications or users.

        The function automatically prevents you from killing your own connection session to avoid disconnecting yourself. You can filter processes by multiple criteria and use it alongside Get-DbaProcess to identify problem sessions before terminating them.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Spid
        Targets specific session IDs (SPIDs) for termination. Use this when you know the exact process ID causing problems, typically identified from blocking reports or activity monitors. You can specify multiple SPIDs to kill several problem sessions at once.

    .PARAMETER Login
        Terminates all active sessions for specified login names. Use this to disconnect all connections from a specific user account, such as when removing user access or troubleshooting login-specific issues. Supports multiple logins and accepts both Windows (DOMAIN\user) and SQL logins.

    .PARAMETER Hostname
        Kills all sessions originating from specified client computer names. Useful when a problematic application server or workstation is creating excessive connections or when you need to force disconnect all sessions from a specific machine. Accepts multiple hostnames including both short names and FQDNs.

    .PARAMETER Program
        Terminates sessions based on the client application name. Use this to disconnect all connections from specific applications like SSMS, poorly-behaved ETL tools, or misbehaving custom applications. Common program names include 'Microsoft SQL Server Management Studio' and various .NET application names.

    .PARAMETER Database
        Kills all active sessions connected to specified databases. Useful when you need to perform exclusive database operations like restores, schema changes, or when preparing for database maintenance. This will disconnect all users currently connected to the targeted databases.

    .PARAMETER ExcludeSpid
        Protects specific session IDs from termination even if they match other filter criteria. Use this to preserve important connections like monitoring tools or critical application sessions when killing processes by login, hostname, or database. This exclusion is applied last, overriding all other matching filters.

    .PARAMETER InputObject
        Accepts process objects from Get-DbaProcess through the pipeline. Use this approach to first identify and review problematic sessions before terminating them, providing better control and verification of which processes will be killed.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Process
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Stop-DbaProcess

    .OUTPUTS
        PSCustomObject

        Returns one object per successfully killed process, confirming the termination action with session details.

        Properties:
        - SqlInstance: The name of the SQL Server instance where the process was terminated
        - Spid: The session ID (SPID) of the killed process
        - Login: The login name associated with the killed process
        - Host: The hostname or computer name where the client process originated
        - Database: The name of the database the killed session was connected to
        - Program: The application or program name that initiated the killed session
        - Status: Always set to "Killed" to confirm successful process termination

        Note: Processes matching filter criteria but matching ExcludeSpid, or the current session, or processes that fail to kill will not generate output objects.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Login base\ctrlb, sa

        Finds all processes for base\ctrlb and sa on sqlserver2014a, then kills them. Uses Windows Authentication to login to sqlserver2014a.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -SqlCredential $credential -Spid 56, 77

        Finds processes for spid 56 and 57, then kills them. Uses alternative (SQL or Windows) credentials to login to sqlserver2014a.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Program 'Microsoft SQL Server Management Studio'

        Finds processes that were created in Microsoft SQL Server Management Studio, then kills them.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014a -Hostname workstationx, server100

        Finds processes that were initiated (computers/clients) workstationx and server 1000, then kills them.

    .EXAMPLE
        PS C:\> Stop-DbaProcess -SqlInstance sqlserver2014  -Database tempdb -WhatIf

        Shows what would happen if the command were executed.

    .EXAMPLE
        PS C:\> Get-DbaProcess -SqlInstance sql2016 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess

        Finds processes that were created with dbatools, then kills them.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess)]
    param (
        [parameter(Mandatory, ParameterSetName = "Server")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [int[]]$Spid,
        [int[]]$ExcludeSpid,
        [string[]]$Database,
        [string[]]$Login,
        [string[]]$Hostname,
        [string[]]$Program,
        [parameter(ValueFromPipeline, Mandatory, ParameterSetName = "Process")]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject) {
            $bound = $PSBoundParameters
            $null = $bound.Remove("WhatIf")
            $null = $bound.Remove("Confirm")
            $InputObject = Get-DbaProcess @bound
        }

        foreach ($session in $InputObject) {
            $sourceserver = $session.Parent

            if (!$sourceserver) {
                Stop-Function -Message "Only process objects can be passed through the pipeline." -Category InvalidData -Target $session
                return
            }

            $currentspid = $session.spid

            if ($sourceserver.ConnectionContext.ProcessID -eq $currentspid) {
                Write-Message -Level Warning -Message "Skipping spid $currentspid because you cannot use KILL to kill your own process." -Target $session
                Continue
            }

            if ($Pscmdlet.ShouldProcess($sourceserver, "Killing spid $currentspid")) {
                try {
                    $sourceserver.KillProcess($currentspid)
                    [PSCustomObject]@{
                        SqlInstance = $sourceserver.name
                        Spid        = $session.Spid
                        Login       = $session.Login
                        Host        = $session.Host
                        Database    = $session.Database
                        Program     = $session.Program
                        Status      = 'Killed'
                    }
                } catch {
                    Stop-Function -Message "Couldn't kill spid $currentspid." -Target $session -ErrorRecord $_ -Continue
                }
            }
        }
    }
}