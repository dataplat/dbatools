function Remove-DbaDbMailProfile {
    <#
    .SYNOPSIS
        Removes Database Mail profiles from SQL Server instances.

    .DESCRIPTION
        Deletes specified Database Mail profiles from the msdb database, permanently removing their configuration and preventing them from sending emails. 
        This is commonly used during security hardening to remove unused profiles or when cleaning up misconfigured mail setups.
        Accepts profiles via pipeline from Get-DbaDbMailProfile or directly through parameters, making it easy to selectively remove profiles based on specific criteria.
        Returns detailed results showing which profiles were successfully removed and any that failed during deletion.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Profile
        Specifies one or more database mail profile(s) to get. If unspecified, all profiles will be removed.

    .PARAMETER ExcludeProfile
        Specifies one or more database mail profile(s) to exclude.

    .PARAMETER InputObject
        Allows piping from Get-DbaDbMailProfile.

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
        Tags: DatabaseMail, DBMail, Mail
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it

        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbMailProfile

    .EXAMPLE
        PS C:\> Remove-DbaDbMailProfile -SqlInstance localhost, localhost\namedinstance

        Removes all database mail profiles on the localhost, localhost\namedinstance instances.

    .EXAMPLE
        PS C:\> Remove-DbaDbMailProfile -SqlInstance localhost -Profile MyDatabaseMailProfile

        Removes MyDatabaseMailProfile database mail profile on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbMailProfile -SqlInstance SRV1 | Out-GridView -Title 'Select database mail profile(s) to drop' -OutputMode Multiple | Remove-DbaDbMailProfile

        Using a pipeline this command gets all database mail profiles on SRV1, lets the user select those to remove and then removes the selected database mail profiles.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Profile,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeProfile,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Mail.MailProfile[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $dbMailProfiles = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbMailProfiles = Get-DbaDbMailProfile @params
        } else {
            $dbMailProfiles += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbMailProfile.
        foreach ($dbMailProfile in $dbMailProfiles) {
            if ($PSCmdlet.ShouldProcess($dbMailProfile.Parent.Parent.Name, "Removing the database mail profile $($dbMailProfile.Name) on $($dbMailProfile.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbMailProfile.Parent.Parent.ComputerName
                    InstanceName = $dbMailProfile.Parent.Parent.ServiceName
                    SqlInstance  = $dbMailProfile.Parent.Parent.DomainInstanceName
                    Name         = $dbMailProfile.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbMailProfile.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the database mail profile $($dbMailProfile.Name) on $($dbMailProfile.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}