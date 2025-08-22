function Remove-DbaAgentOperator {
    <#
    .SYNOPSIS
        Removes SQL Server Agent operators from one or more instances.

    .DESCRIPTION
        Removes SQL Server Agent operators from specified instances, cleaning up notification contacts that are no longer needed. 
        
        Operators are notification contacts used by SQL Server Agent to send alerts about job failures, system issues, or other events. This function helps you remove outdated operator accounts when employees leave, contact information changes, or you need to consolidate notification lists.
        
        The function safely handles dependencies and provides detailed status output for each removal operation, making it suitable for both interactive cleanup and automated operator management scripts.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Operator
        Name of the operator in SQL Agent.

    .PARAMETER ExcludeOperator
        The operator(s) to exclude.

    .PARAMETER InputObject
        Allows piping from Get-DbaAgentOperator.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        SMO Server Objects (pipeline input from Connect-DbaInstance)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Agent, Operator
        Author: Tracy Boggiano (@TracyBoggiano), databasesuperhero.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentOperator

    .EXAMPLE
        PS C:\> Remove-DbaAgentOperator -SqlInstance sql01 -Operator DBA

        This removes an operator named DBA from the instance.

    .EXAMPLE
        PS C:\> Get-DbaAgentOperator -SqlInstance SRV1 | Out-GridView -Title 'Select SQL Agent operator(s) to drop' -OutputMode Multiple | Remove-DbaAgentOperator

        Using a pipeline this command gets all SQL Agent operator(s) on SRV1, lets the user select those to remove and then removes the selected SQL Agent alert category(-ies).

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Operator,
        [string[]]$ExcludeOperator,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Agent.Operator[]]$InputObject,
        [switch]$EnableException
    )

    begin {
        $dbOperators = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbOperators = Get-DbaAgentOperator @params
        } else {
            $dbOperators += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentOperator.
        foreach ($dbOperator in $dbOperators) {
            if ($PSCmdlet.ShouldProcess($dbOperator.Parent.Parent.Name, "Removing the SQL Agent operator $($dbOperator.Name) on $($dbOperator.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbOperator.Parent.Parent.ComputerName
                    InstanceName = $dbOperator.Parent.Parent.ServiceName
                    SqlInstance  = $dbOperator.Parent.Parent.DomainInstanceName
                    Name         = $dbOperator.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbOperator.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the SQL Agent operator $($dbOperator.Name) on $($dbOperator.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}