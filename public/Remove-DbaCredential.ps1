function Remove-DbaCredential {
    <#
    .SYNOPSIS
        Removes SQL credential(s).

    .DESCRIPTION
        Removes the SQL credential(s) that have passed through the pipeline.
        If not used with a pipeline, Get-DbaCredential will be executed with the parameters provided
        and the returned SQL credential(s) will be removed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Specifies one or more SQL Server credential names to remove from the instance. Accepts wildcards for pattern matching.
        Use this to target specific credentials instead of removing all credentials on the server.

    .PARAMETER ExcludeCredential
        Specifies one or more SQL Server credential names to exclude from removal. Accepts wildcards for pattern matching.
        Use this when you want to remove most credentials but preserve certain ones like service account or backup credentials.

    .PARAMETER Identity
        Filters credentials by their associated identity (the Windows account or certificate the credential represents).
        Use this to remove credentials based on the underlying identity rather than the credential name. Enclose identities with spaces in quotes.

    .PARAMETER ExcludeIdentity
        Specifies identities to exclude from credential removal operations.
        Use this to preserve credentials associated with specific Windows accounts or certificates when removing others.

    .PARAMETER InputObject
        Accepts credential objects from Get-DbaCredential for pipeline operations.
        Use this to chain credential discovery and removal operations, enabling selective removal through Out-GridView or other filters.

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
        Tags: Security, Credential
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it
        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaCredential

    .EXAMPLE
        PS C:\> Remove-DbaCredential -SqlInstance localhost, localhost\namedinstance

        Removes all SQL credentials on the localhost, localhost\namedinstance instances.

    .EXAMPLE
        PS C:\> Remove-DbaCredential -SqlInstance localhost -Credential MyDatabaseCredential

        Removes MyDatabaseCredential SQL credential on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaCredential -SqlInstance SRV1 | Out-GridView -Title 'Select SQL credential(s) to drop' -OutputMode Multiple | Remove-DbaCredential

        Using a pipeline this command gets all SQL credentials on SRV1, lets the user select those to remove and then removes the selected SQL credentials.

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Default', ConfirmImpact = 'High')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Credential,
        [string[]]$ExcludeCredential,
        [string[]]$Identity,
        [string[]]$ExcludeIdentity,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Credential[]]$InputObject,
        [Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $dbCredentials = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbCredentials = Get-DbaCredential @params
        } else {
            $dbCredentials += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaCredential.
        foreach ($dbCredential in $dbCredentials) {
            if ($PSCmdlet.ShouldProcess($dbCredential.Parent.Name, "Removing the SQL credential $($dbCredential.Name) on $($dbCredential.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbCredential.ComputerName
                    InstanceName = $dbCredential.InstanceName
                    SqlInstance  = $dbCredential.SqlInstance
                    Name         = $dbCredential.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbCredential.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the SQL credential $($dbCredential.Name) on $($dbCredential.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}