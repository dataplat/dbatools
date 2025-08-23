function Remove-DbaAgentAlert {
    <#
    .SYNOPSIS
        Removes SQL Server Agent alerts from specified instances.

    .DESCRIPTION
        Deletes SQL Server Agent alerts that monitor for specific errors, performance conditions, or system events.
        Useful for cleaning up obsolete alerts, removing test configurations, or managing alert policies across multiple instances.
        Can remove specific alerts by name, exclude certain alerts, or work with piped input from Get-DbaAgentAlert for selective removal.
        Returns detailed results showing which alerts were successfully removed and any errors encountered.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Alert
        Specifies the names of specific SQL Agent alerts to remove from the target instances.
        Use this when you need to remove particular alerts rather than all alerts on the server.
        Accepts an array of alert names for bulk removal operations.

    .PARAMETER ExcludeAlert
        Excludes specific SQL Agent alerts from removal when processing all alerts on an instance.
        Useful for bulk cleanup operations where you want to preserve certain critical alerts.
        Only applies when the Alert parameter is not specified, allowing you to remove all alerts except those listed here.

    .PARAMETER InputObject
        Accepts SQL Agent alert objects from the pipeline, typically from Get-DbaAgentAlert.
        Use this for selective removal operations where you first query alerts with specific criteria and then remove the filtered results.
        Enables advanced scenarios like interactive selection using Out-GridView or complex filtering logic.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.
        This is the default. Use -Confirm:$false to suppress these prompts.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Alert
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it
        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentAlert

    .EXAMPLE
        PS C:\> Remove-DbaAgentAlert -SqlInstance localhost, localhost\namedinstance

        Removes all SQL Agent alerts on the localhost, localhost\namedinstance instances.

    .EXAMPLE
        PS C:\> Remove-DbaAgentAlert -SqlInstance localhost -Alert MyDatabaseAlert

        Removes MyDatabaseAlert SQL Agent alert on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaAgentAlert -SqlInstance SRV1 | Out-GridView -Title 'Select SQL Agent alert(s) to drop' -OutputMode Multiple | Remove-DbaAgentAlert

        Using a pipeline this command gets all SQL Agent alerts on SRV1, lets the user select those to remove and then removes the selected SQL Agent alerts.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Alert,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeAlert,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Agent.Alert[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $dbAlerts = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbAlerts = Get-DbaAgentAlert @params
        } else {
            $dbAlerts += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentAlert.
        foreach ($dbAlert in $dbAlerts) {
            if ($PSCmdlet.ShouldProcess($dbAlert.Parent.Parent.Name, "Removing the SQL Agent alert $($dbAlert.Name) on $($dbAlert.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbAlert.Parent.Parent.ComputerName
                    InstanceName = $dbAlert.Parent.Parent.ServiceName
                    SqlInstance  = $dbAlert.Parent.Parent.DomainInstanceName
                    Name         = $dbAlert.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbAlert.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the SQL Agent alert $($dbAlert.Name) on $($dbAlert.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}