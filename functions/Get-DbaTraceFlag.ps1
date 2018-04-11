function Get-DbaTraceFlag {
    <#
        .SYNOPSIS
            Get global Trace Flag(s) information for each instance(s) of SQL Server.

        .DESCRIPTION
            Returns Trace Flags that are enabled globally on each instance(s) of SQL Server as an object.

        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER TraceFlag
            Use this switch to filter to a specific Trace Flag.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: TraceFlag
            Author: Kevin Bullen (@sqlpadawan)

            References:  https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaTraceFlag

        .EXAMPLE
            Get-DbaTraceFlag -SqlInstance localhost

            Returns all Trace Flag information on the local default SQL Server instance

        .EXAMPLE
            Get-DbaTraceFlag -SqlInstance localhost, sql2016

            Returns all Trace Flag(s) for the local and sql2016 SQL Server instances

        .EXAMPLE
            Get-DbaTraceFlag -SqlInstance localhost -TraceFlag 4199,3205

            Returns Trace Flag status for TF 4199 and 3205 for the local SQL Server instance if they are enabled.
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [int[]]$TraceFlag,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $tflags = $server.EnumActiveGlobalTraceFlags()

            if ($tFlags.Rows.Count -eq 0) {
                Write-Message -Level Output -Message "No global trace flags enabled"
                return
            }

            if ($TraceFlag) {
                $tflags = $tflags | Where-Object TraceFlag -In $TraceFlag
            }

            foreach ($tflag in $tflags) {
                [pscustomobject]@{
                    ComputerName = $server.NetName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    TraceFlag    = $tflag.TraceFlag
                    Global       = $tflag.Global
                    Session      = $tflag.Session
                    Status       = $tflag.Status
                } | Select-DefaultView -ExcludeProperty 'Session'
            }
        }
    }
}
