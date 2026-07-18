function Get-DbaInstanceAudit {
    <#
    .SYNOPSIS
        Retrieves SQL Server audit objects from instance-level security auditing configurations.

    .DESCRIPTION
        Retrieves all configured SQL Server audit objects at the instance level, which define where security audit events are stored and how they're managed. These audits capture login attempts, permission changes, and other security-related activities across the entire SQL Server instance. The function returns detailed information including audit file paths, size limits, rollover settings, and current status, helping DBAs monitor compliance and troubleshoot security configurations without manually querying system views.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Audit
        Specifies which audit objects to retrieve by name. Accepts multiple audit names to return only those specific audits.
        Use this when you need to check configuration or status for particular audits instead of retrieving all instance-level audits.

    .PARAMETER ExcludeAudit
        Specifies which audit objects to exclude from results by name. Accepts multiple audit names to filter out unwanted audits.
        Use this when you want to retrieve most audits but skip specific ones, such as excluding test or temporary audits from compliance reports.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Audit, Security, SqlAudit
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaInstanceAudit

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Audit

        Returns one Audit object for each SQL Server audit configured at the instance level.

        Default display properties (via Select-DefaultView):
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the SQL Server audit
        - IsEnabled: Boolean indicating if the audit is currently enabled
        - OnFailure: Action to take when an audit event cannot be written (Continue, Shutdown, FailOperation)
        - MaximumFiles: Maximum number of audit files to retain
        - MaximumFileSize: Maximum size for each audit file
        - MaximumFileSizeUnit: Unit of measurement for MaximumFileSize (Megabyte, Gigabyte, Terabyte)
        - MaximumRolloverFiles: Number of files to rollover before recycling the oldest file
        - QueueDelay: Delay in milliseconds before flushing audit records to the audit target
        - ReserveDiskSpace: Boolean indicating if disk space equal to MaximumFileSize is pre-allocated
        - FullName: Full local file path where audit events are stored

        Additional properties available:
        - RemoteFullName: Remote UNC path to the audit file location (\\computername\c$\path\filename)
        - FilePath: Directory path where audit files are stored
        - FileName: Name of the audit file
        - Enabled: Same as IsEnabled property

        All properties from the base SMO Audit object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaInstanceAudit -SqlInstance localhost

        Returns all Security Audits on the local default SQL Server instance

    .EXAMPLE
        PS C:\> Get-DbaInstanceAudit -SqlInstance localhost, sql2016

        Returns all Security Audits for the local and sql2016 SQL Server instances

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Audit,
        [string[]]$ExcludeAudit,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $audits = $server.Audits

            if (Test-Bound -ParameterName Audit) {
                $audits = $audits | Where-Object Name -in $Audit
            }
            if (Test-Bound -ParameterName ExcludeAudit) {
                $audits = $audits | Where-Object Name -notin $ExcludeAudit
            }

            foreach ($currentaudit in $audits) {
                $directory = $currentaudit.FilePath.TrimEnd("\")
                $filename = $currentaudit.FileName
                $fullname = "$directory\$filename"
                $remote = $fullname.Replace(":", "$")
                $remote = "\\$($currentaudit.Parent.ComputerName)\$remote"

                Add-Member -Force -InputObject $currentaudit -MemberType NoteProperty -Name ComputerName -value $currentaudit.Parent.ComputerName
                Add-Member -Force -InputObject $currentaudit -MemberType NoteProperty -Name InstanceName -value $currentaudit.Parent.ServiceName
                Add-Member -Force -InputObject $currentaudit -MemberType NoteProperty -Name SqlInstance -value $currentaudit.Parent.DomainInstanceName
                Add-Member -Force -InputObject $currentaudit -MemberType NoteProperty -Name FullName -value $fullname
                Add-Member -Force -InputObject $currentaudit -MemberType NoteProperty -Name RemoteFullName -value $remote

                Select-DefaultView -InputObject $currentaudit -Property ComputerName, InstanceName, SqlInstance, Name, 'Enabled as IsEnabled', OnFailure, MaximumFiles, MaximumFileSize, MaximumFileSizeUnit, MaximumRolloverFiles, QueueDelay, ReserveDiskSpace, FullName
            }
        }
    }
}