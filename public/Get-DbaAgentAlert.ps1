function Get-DbaAgentAlert {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent alert configurations from one or more instances

    .DESCRIPTION
        Retrieves alert configurations from SQL Server Agent, including alert names, types, severity levels, message IDs, and notification settings. Use this to audit alert configurations across multiple servers, troubleshoot missing or misconfigured alerts, or gather information for compliance reporting. The function returns detailed alert properties like enabled status, last occurrence dates, and response delays, making it essential for monitoring your alerting infrastructure and ensuring critical system events are properly configured for notification.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Alert
        Specifies the specific SQL Agent alert names to retrieve from the target instances. Accepts wildcards for pattern matching.
        Use this when you need to check specific alerts like 'Severity 016*' or 'DB Mail*' instead of retrieving all alerts on the server.

    .PARAMETER ExcludeAlert
        Specifies SQL Agent alert names to exclude from the results. Accepts wildcards for pattern matching.
        Use this to filter out unwanted alerts when auditing or when you need to focus on specific alert categories without built-in system alerts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert
        Author: Klaas Vandenberghe (@PowerDBAKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentAlert

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Alert

        Returns one Alert object per SQL Agent alert found on the specified instances.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Name of the alert
        - ID: Unique identifier of the alert in the msdb database
        - JobName: Name of the job that responds to this alert (if any)
        - AlertType: Type of alert (EventAlert, ErrorNumberAlert, etc.)
        - CategoryName: Category name assigned to the alert
        - Severity: SQL Server error severity level (0-25) that triggers this alert
        - MessageId: SQL Server message ID that triggers this alert (if alert is message-based)
        - IsEnabled: Boolean indicating if the alert is enabled
        - DelayBetweenResponses: Delay in seconds between repeated alert responses
        - LastRaised: DateTime when this alert was last triggered (dbatools custom property)
        - OccurrenceCount: Number of times this alert has been raised

        Additional properties available (from SMO Alert object):
        - CategoryId: Unique identifier of the alert category
        - CreateDate: DateTime when the alert was created
        - DateLastModified: DateTime when the alert was last modified
        - DatabaseName: Name of the database this alert applies to (for database-specific alerts)
        - Urn: Uniform Resource Name for the SMO object
        - State: SMO object state (Existing, Creating, Pending, etc.)

        Custom properties added by this function:
        - Notifications: DataTable from EnumNotifications() containing operators notified by this alert and their notification methods (Email, Pager, NetSend)

        All properties from the base SMO Alert object are accessible even though only default properties are displayed without using Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaAgentAlert -SqlInstance ServerA,ServerB\instanceB

        Returns all SQL Agent alerts on serverA and serverB\instanceB

    .EXAMPLE
        PS C:\> Get-DbaAgentAlert -SqlInstance ServerA,ServerB\instanceB -Alert MyAlert*

        Returns SQL Agent alert on serverA and serverB\instanceB whose names match 'MyAlert*'

    .EXAMPLE
        PS C:\> 'serverA','serverB\instanceB' | Get-DbaAgentAlert

        Returns all SQL Agent alerts  on serverA and serverB\instanceB

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Alert,
        [string[]]$ExcludeAlert,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Debug -Message "Getting Edition from $server"
            Write-Message -Level Debug -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
            }

            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "JobName", "AlertType", "CategoryName", "Severity", "MessageId", "IsEnabled", "DelayBetweenResponses", "LastRaised", "OccurrenceCount"

            $alerts = $server.Jobserver.Alerts

            if (Test-Bound 'Alert') {
                $tempAlerts = @()

                foreach ($a in $Alert) {
                    $tempAlerts += $alerts | Where-Object Name -like $a
                }

                $alerts = $tempAlerts
            }

            if (Test-Bound 'ExcludeAlert') {
                foreach ($e in $ExcludeAlert) {
                    $alerts = $alerts | Where-Object Name -notlike $e
                }
            }

            foreach ($alrt in $alerts) {
                $lastraised = [dbadatetime]$alrt.LastOccurrenceDate

                Add-Member -Force -InputObject $alrt -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                Add-Member -Force -InputObject $alrt -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $alrt -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $alrt -MemberType NoteProperty Notifications -value $alrt.EnumNotifications()
                Add-Member -Force -InputObject $alrt -MemberType NoteProperty LastRaised -value $lastraised

                Select-DefaultView -InputObject $alrt -Property $defaults
            }
        }
    }
}