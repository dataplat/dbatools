function New-DbaDbMailProfile {
    <#
    .SYNOPSIS
        Creates a new database mail profile

    .DESCRIPTION
        Creates a new database mail profile, and optionally associates it to a database mail account

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Name
        The Name of the profile to be created.

    .PARAMETER Description
        Sets the description of the purpose of the mail profile.

    .PARAMETER MailAccountName
        Associates a db mail account to link to this db mail profile.

    .PARAMETER MailAccountPriority
        Sets the priority of the linked db mail account when linking to this db mail profile.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DbMail
        Author: Ian Lanham (@ilanham)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbMailProfile

    .EXAMPLE
        PS C:\> $profile = New-DbaDbMailProfile -SqlInstance sql2017 -Name 'The DBA Team'

        Creates a new db mail profile

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$Name,
        [string]$Description,
        [string]$MailAccountName,
        [int]$MailAccountPriority,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Creating new db mail profile called $Name")) {
                try {
                    $profile = New-Object Microsoft.SqlServer.Management.SMO.Mail.MailProfile $server.Mail, $Name
                    if (Test-Bound -ParameterName 'Description') {
                        $profile.Description = $Description
                    }
                    $profile.Create()
                    if (Test-Bound -ParameterName 'MailAccountName') {
                        if (!$MailAccountPriority) {
                            $MailAccountPriority = 1
                        }
                        $profile.AddAccount($MailAccountName, $MailAccountPriority) # sequenceNumber correlates to "Priority" when associating a db mail Account to a db mail Profile
                    }
                    Add-Member -Force -InputObject $profile -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $profile -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $profile -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                    $profile | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, Description, IsBusyProfile
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}