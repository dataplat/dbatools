function Remove-DbaDbMailAccount {
    <#
    .SYNOPSIS
        Removes Database Mail accounts from SQL Server instances

    .DESCRIPTION
        Permanently deletes Database Mail accounts from the specified SQL Server instances, removing them from the MSDB database configuration.
        This command is useful when decommissioning obsolete email accounts, cleaning up after application retirement, or consolidating accounts during email system migrations.
        When used without pipeline input, it automatically retrieves accounts using Get-DbaDbMailAccount with the provided parameters before removal.
        Returns detailed status information for each removal operation, including success/failure status and any error messages encountered.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Account
        Specifies one or more database mail account(s) to delete. If unspecified, all accounts will be removed.

    .PARAMETER ExcludeAccount
        Specifies one or more database mail account(s) to exclude.

    .PARAMETER InputObject
        Allows piping from Get-DbaDbMailAccount.

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
        Tags: DatabaseMail, DbMail, Mail
        Author: Mikey Bronowski (@MikeyBronowski), bronowski.it
        dbatools PowerShell module (https://dbatools.io)
        Copyright: (c) 2021 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaDbMailAccount

    .EXAMPLE
        PS C:\> Remove-DbaDbMailAccount -SqlInstance localhost, localhost\namedinstance

        Removes all database mail accounts on the localhost, localhost\namedinstance instances.

    .EXAMPLE
        PS C:\> Remove-DbaDbMailAccount -SqlInstance localhost -Account MyDatabaseMailAccount

        Removes MyDatabaseMailAccount database mail account on the localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbMailAccount -SqlInstance SRV1 | Out-GridView -Title 'Select database mail account(s) to drop' -OutputMode Multiple | Remove-DbaDbMailAccount

        Using a pipeline this command gets all database mail accounts on SRV1, lets the user select those to remove and then removes the selected database mail accounts.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$Account,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [string[]]$ExcludeAccount,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Mail.MailAccount[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException
    )

    begin {
        $dbMailAccounts = @( )
    }

    process {
        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $dbMailAccounts = Get-DbaDbMailAccount @params
        } else {
            $dbMailAccounts += $InputObject
        }
    }

    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaDbMailAccount.
        foreach ($dbMailAccount in $dbMailAccounts) {
            if ($PSCmdlet.ShouldProcess($dbMailAccount.Parent.Parent.Name, "Removing the database mail account $($dbMailAccount.Name) on $($dbMailAccount.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
                    ComputerName = $dbMailAccount.Parent.Parent.ComputerName
                    InstanceName = $dbMailAccount.Parent.Parent.ServiceName
                    SqlInstance  = $dbMailAccount.Parent.Parent.DomainInstanceName
                    Name         = $dbMailAccount.Name
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    $dbMailAccount.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the database mail account $($dbMailAccount.Name) on $($dbMailAccount.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}