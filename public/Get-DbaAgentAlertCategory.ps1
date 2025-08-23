function Get-DbaAgentAlertCategory {
    <#
    .SYNOPSIS
        Retrieves SQL Server Agent alert categories and their associated alert counts

    .DESCRIPTION
        Retrieves all SQL Server Agent alert categories from the target instances, showing how alerts are organized and grouped. Categories help DBAs manage alerts logically by grouping related notifications (such as severity-based alerts, database maintenance alerts, or custom business alerts). The function also returns a count of how many alerts are currently assigned to each category, making it useful for understanding your alerting structure and identifying unused or heavily-used categories.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        Specifies one or more alert category names to return from the SQL Server Agent. Accepts multiple values and wildcards are not supported.
        Use this when you need to examine specific alert categories rather than retrieving all categories on the instance.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert, AlertCategory
        Author: Patrick Flynn (@sqllensman)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgentAlertCategory

    .EXAMPLE
        PS C:\> Get-DbaAgentAlertCategory -SqlInstance sql1

        Return all the agent alert categories.

    .EXAMPLE
        PS C:\> Get-DbaAgentAlertCategory -SqlInstance sql1 -Category 'Severity Alert'

        Return all the agent alert categories that have the name 'Severity Alert'.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Category,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $alertCategories = $server.JobServer.AlertCategories
            if (Test-Bound -ParameterName Category) {
                $alertCategories = $alertCategories | Where-Object { $_.Name -in $Category }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'ID', 'AlertCount'

            try {
                foreach ($cat in $alertCategories) {
                    $alertCount = ($server.JobServer.Alerts | Where-Object { $_.CategoryName -eq $cat.Name }).Count

                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $cat -MemberType NoteProperty -Name AlertCount -Value $alertCount

                    Select-DefaultView -InputObject $cat -Property $defaults
                }
            } catch {
                Stop-Function -Message "Something went wrong getting the alert category $cat on $instance" -Target $cat -Continue -ErrorRecord $_
            }
        }
    }
}