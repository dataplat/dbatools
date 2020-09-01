function Get-DbaAgentLog {
    <#
    .SYNOPSIS
        Gets the "SQL Agent Error Log" of an instance

    .DESCRIPTION
        Gets the "SQL Agent Error Log" of an instance. Returns all 10 error logs by default.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogNumber
        An Int32 value that specifies the index number of the error log required. Error logs are listed 0 through 9 where 0 is the current error log and 9 is the oldest.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentLog

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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