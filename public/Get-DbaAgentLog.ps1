function Get-DbaAgentLog {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent error log entries for troubleshooting and monitoring

    .DESCRIPTION
        Retrieves SQL Server Agent error log entries from the target instance, providing detailed information about agent service activity, job failures, and system events. This function accesses the agent's historical error logs (numbered 0-9, where 0 is the current log) so you don't have to manually navigate through SQL Server Management Studio or query system views. Essential for troubleshooting job failures, monitoring agent service health, and compliance auditing of automated processes.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogNumber
        Specifies which numbered agent error log files to retrieve (0-9). Log 0 contains the most recent entries, while higher numbers contain older historical logs that get cycled as new logs are created.
        Use this when you need to examine historical agent activity or troubleshoot issues that occurred days or weeks ago, rather than just current entries.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentLog

    .OUTPUTS
        System.Data.DataRow

        Returns one DataRow object per log entry found. If multiple log numbers are specified, all entries from all requested log files are returned.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - LogDate: The date and time when the log entry was created (DateTime)
        - ProcessInfo: The process ID or source component that created the entry (typically spid or component name)
        - Text: The full text content of the log entry message

    .EXAMPLE
        PS C:\> Get-DbaAgentLog -SqlInstance sql01\sharepoint

        Returns the entire error log for the SQL Agent on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaAgentLog -SqlInstance sql01\sharepoint -LogNumber 3, 6

        Returns log numbers 3 and 6 for the SQL Agent on sql01\sharepoint

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaAgentLog -LogNumber 0

        Returns the most recent SQL Agent error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [ValidateRange(0, 9)]
        [int[]]$LogNumber,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($LogNumber) {
                foreach ($number in $lognumber) {
                    try {
                        foreach ($object in $server.JobServer.ReadErrorLog($number)) {
                            Write-Message -Level Verbose -Message "Processing $object"
                            Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.ComputerName
                            Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                            Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                            # Select all of the columns you'd like to show
                            Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, ProcessInfo, Text
                        }
                    } catch {
                        Stop-Function -Continue -Target $server -Message "Could not read from SQL Server Agent"
                    }
                }
            } else {
                try {
                    foreach ($object in $server.JobServer.ReadErrorLog()) {
                        Write-Message -Level Verbose -Message "Processing $object"
                        Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.ComputerName
                        Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                        Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                        # Select all of the columns you'd like to show
                        Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, ProcessInfo, Text
                    }
                } catch {
                    Stop-Function -Continue -Target $server -Message "Could not read from SQL Server Agent"
                }
            }
        }
    }
}