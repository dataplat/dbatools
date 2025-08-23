function Get-DbaTraceFlag {
    <#
    .SYNOPSIS
        Retrieves currently enabled global trace flags from SQL Server instances.

    .DESCRIPTION
        Queries SQL Server instances to identify which global trace flags are currently active, returning detailed status information for monitoring and compliance purposes. This is essential for auditing server configurations, troubleshooting performance issues, and ensuring trace flag consistency across environments. You can filter results to specific trace flag numbers or retrieve all enabled flags across multiple instances.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER TraceFlag
        Use this switch to filter to a specific Trace Flag.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, TraceFlag, DBCC
        Author: Kevin Bullen (@sqlpadawan)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        References:  https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql

    .LINK
        https://dbatools.io/Get-DbaTraceFlag

    .EXAMPLE
        PS C:\> Get-DbaTraceFlag -SqlInstance localhost

        Returns all Trace Flag information on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaTraceFlag -SqlInstance localhost, sql2016

        Returns all Trace Flag(s) for the local and sql2016 SQL Server instances

    .EXAMPLE
        PS C:\> Get-DbaTraceFlag -SqlInstance localhost -TraceFlag 4199,3205

        Returns Trace Flag status for TF 4199 and 3205 for the local SQL Server instance if they are enabled.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [int[]]$TraceFlag,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $tflags = $server.EnumActiveGlobalTraceFlags()

            if ($tFlags.Rows.Count -eq 0) {
                Write-Message -Level Verbose -Message "No global trace flags enabled"
                continue
            }

            if ($TraceFlag) {
                $tflags = $tflags | Where-Object TraceFlag -In $TraceFlag
            }

            foreach ($tflag in $tflags) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
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