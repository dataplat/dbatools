function Get-DbaAgentAlert {
    <#
    .SYNOPSIS
    Returns all SQL Agent alerts on a SQL Server Agent.

    .DESCRIPTION
    This function returns SQL Agent alerts.

    .PARAMETER SqlInstance
    SqlInstance name or SMO object representing the SQL Server to connect to.
    This can be a collection and receive pipeline input.

    .PARAMETER SqlCredential
    PSCredential object to connect as. If not specified, current Windows login will be used.

    .NOTES
    Author: Klaas Vandenberghe ( @PowerDBAKlaas )
    Tags: Agent, SMO
    Website: https://dbatools.io
    Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
    License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .LINK
    https://dbatools.io/Get-DbaAgentAlert

    .EXAMPLE
    Get-DbaAgentAlert -SqlInstance ServerA,ServerB\instanceB
    Returns all SQL Agent alerts on serverA and serverB\instanceB

    .EXAMPLE
    'serverA','serverB\instanceB' | Get-DbaAgentAlert
    Returns all SQL Agent alerts  on serverA and serverB\instanceB

#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "Instance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance"
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting Edition from $server"
            Write-Message -Level Verbose -Message "$server is a $($server.Edition)"

            if ($server.Edition -like 'Express*') {
                Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
            }

            $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "JobName", "AlertType", "CategoryName", "Severity", "IsEnabled", "DelayBetweenResponses", "LastRaised", "OccurrenceCount"

            $alerts = $server.Jobserver.Alerts

            foreach ($alert in $alerts) {
                $lastraised = [dbadatetime]$alert.LastOccurrenceDate

                Add-Member -Force -InputObject $alert -MemberType NoteProperty -Name ComputerName -value $server.NetName
                Add-Member -Force -InputObject $alert -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                Add-Member -Force -InputObject $alert -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                Add-Member -Force -InputObject $alert -MemberType NoteProperty Notifications -value $alert.EnumNotifications()
                Add-Member -Force -InputObject $alert -MemberType NoteProperty LastRaised -value $lastraised

                Select-DefaultView -InputObject $alert -Property $defaults
            }
        }
    }
}