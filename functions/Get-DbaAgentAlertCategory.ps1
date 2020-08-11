function Get-DbaAgentAlertCategory {
    <#
    .SYNOPSIS
        Get-DbaAgentAlertCategory retrieves the alert categories.

    .DESCRIPTION
        Get-DbaAgentAlertCategory makes it possible to retrieve the alert categories.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Category
        The name of the category to filter out. If no category is used all categories will be returned.

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
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
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