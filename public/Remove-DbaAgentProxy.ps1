function Remove-DbaAgentProxy {
    <#
    .SYNOPSIS
        Removes SQL Agent agent proxy(s).

    .DESCRIPTION
        Removes the SQL Agent proxy(s) that have passed through the pipeline.
        If not used with a pipeline, Get-DbaAgentProxy will be executed with the parameters provided
        and the returned SQL Agent proxy(s) will be removed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Proxy
        Specifies one or more SQL Agent proxy account names to remove. Accepts wildcards for pattern matching.
        Use this when you need to remove specific proxy accounts instead of all proxies on the instance.
        Common examples include service account proxies or job-specific proxy accounts that are no longer needed.

    .PARAMETER ExcludeProxy
        Specifies one or more SQL Agent proxy account names to exclude from removal. Accepts wildcards for pattern matching.
        Use this when removing multiple proxies but want to preserve certain critical proxy accounts.
        Helpful for bulk cleanup operations while protecting production service account proxies.

    .PARAMETER InputObject
        Accepts SQL Agent proxy objects from the pipeline, typically from Get-DbaAgentProxy.
        Use this parameter set when you need to filter or select specific proxies before removal.
        Enables advanced scenarios like interactive selection through Out-GridView or complex filtering logic.

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
        Tags: Agent, Proxy
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it
        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentProxy

    .EXAMPLE
        PS C:\> Remove-DbaAgentProxy -SqlInstance localhost, localhost\namedinstance

        Removes all SQL Agent proxies on the localhost, localhost\namedinstance instances.

    .EXAMPLE
        PS C:\> Remove-DbaAgentProxy -SqlInstance localhost -Proxy MyDatabaseProxy

        Removes MyDatabaseProxy SQL Agent proxy on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaAgentProxy -SqlInstance SRV1 | Out-GridView -Title 'Select SQL Agent proxy(s) to drop' -OutputMode Multiple | Remove-DbaAgentProxy

        Using a pipeline this command gets all SQL Agent proxies on SRV1, lets the user select those to remove and then removes the selected SQL Agent proxies.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Proxy,
        [string[]]$ExcludeProxy,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Agent.ProxyAccount[]]$InputObject,
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $dbProxies = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbProxies = Get-DbaAgentProxy @params
        } else {
            $dbProxies += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentProxy.
        foreach ($dbProxy in $dbProxies) {
            if ($PSCmdlet.ShouldProcess($dbProxy.Parent.Parent.Name, "Removing the SQL Agent proxy $($dbProxy.Name) on $($dbProxy.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbProxy.Parent.Parent.ComputerName
                    InstanceName = $dbProxy.Parent.Parent.ServiceName
                    SqlInstance  = $dbProxy.Parent.Parent.DomainInstanceName
                    Name         = $dbProxy.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbProxy.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the SQL Agent proxy $($dbProxy.Name) on $($dbProxy.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}