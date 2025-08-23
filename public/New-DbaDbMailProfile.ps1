function New-DbaDbMailProfile {
    <#
    .SYNOPSIS
        Creates a new Database Mail profile for organizing SQL Server email notifications

    .DESCRIPTION
        Creates a new Database Mail profile on SQL Server instances, which serves as a container for organizing mail accounts used by SQL Server for notifications, alerts, and reports. Database Mail profiles allow you to group multiple mail accounts and set priorities for failover scenarios. You can optionally associate an existing mail account to the profile during creation, making this useful for setting up complete email notification systems or organizing different notification types into separate profiles.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2008 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Profile
        Specifies the name for the new Database Mail profile. Profile names must be unique within each SQL Server instance.
        Use descriptive names like 'DBA Alerts', 'Application Notifications', or 'Backup Reports' to organize different types of email notifications.

    .PARAMETER Description
        Provides a detailed description explaining the purpose or intended use of the Database Mail profile.
        This helps document what types of emails will be sent through this profile, making it easier for other DBAs to understand the profile's purpose.

    .PARAMETER MailAccountName
        Specifies an existing Database Mail account to associate with this profile during creation.
        The mail account must already exist on the SQL Server instance and will be used to send emails through this profile.

    .PARAMETER MailAccountPriority
        Sets the priority level for the associated mail account within the profile, with 1 being the highest priority.
        Lower priority accounts serve as failover options when higher priority accounts are unavailable. Defaults to 1 if not specified.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DbMail, Mail
        Author: Ian Lanham (@ilanham)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/New-DbaDbMailProfile

    .EXAMPLE
        PS C:\> $profile = New-DbaDbMailProfile -SqlInstance sql2017 -Profile 'The DBA Team'

        Creates a new database mail profile.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [Alias("Name")]
        [string]$Profile,
        [string]$Description,
        [string]$MailAccountName,
        [int]$MailAccountPriority,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Pscmdlet.ShouldProcess($instance, "Creating new db mail profile called $Profile")) {
                try {
                    $profileObj = New-Object Microsoft.SqlServer.Management.SMO.Mail.MailProfile $server.Mail, $Profile
                    if (Test-Bound -ParameterName 'Description') {
                        $profileObj.Description = $Description
                    }
                    $profileObj.Create()
                    if (Test-Bound -ParameterName 'MailAccountName') {
                        if (!$MailAccountPriority) {
                            $MailAccountPriority = 1
                        }
                        $profileObj.AddAccount($MailAccountName, $MailAccountPriority) # sequenceNumber correlates to "Priority" when associating a db mail Account to a db mail Profile
                    }
                    Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $profileObj -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName

                    $profileObj | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Id, Name, Description, IsBusyProfile
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
        }
    }
}