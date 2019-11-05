function Get-DbaDbMailProfile {
    <#
    .SYNOPSIS
        Gets database mail profiles from SQL Server

    .DESCRIPTION
        Gets database mail profiles from SQL Server

    .PARAMETER SqlInstance
        TThe target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Profile
        Specifies one or more profile(s) to get. If unspecified, all profiles will be returned.

    .PARAMETER ExcludeProfile
        Specifies one or more profile(s) to exclude.

    .PARAMETER InputObject
        Accepts pipeline input from Get-DbaDbMail

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DatabaseMail, DBMail, Mail
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbMailProfile

    .EXAMPLE
        PS C:\> Get-DbaDbMailProfile -SqlInstance sql01\sharepoint

        Returns DBMail profiles on sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailProfile -SqlInstance sql01\sharepoint -Profile 'The DBA Team'

        Returns The DBA Team DBMail profile from sql01\sharepoint

    .EXAMPLE
        PS C:\> Get-DbaDbMailProfile -SqlInstance sql01\sharepoint | Select-Object *

        Returns the DBMail profiles on sql01\sharepoint then return a bunch more columns

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMail | Get-DbaDbMailProfile

        Returns the DBMail profiles for "sql2014","sql2016" and "sqlcluster\sharepoint"

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Profile,
        [string[]]$ExcludeProfile,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Mail.SqlMail[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDbMail -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }

        if (-not $InputObject) {
            Stop-Function -Message "No servers to process"
            return
        }

        foreach ($mailserver in $InputObject) {
            try {
                $profiles = $mailserver.Profiles

                if ($Profile) {
                    $profiles = $profiles | Where-Object Name -in $Profile
                }

                If ($ExcludeProfile) {
                    $profiles = $profiles | Where-Object Name -notin $ExcludeProfile

                }

                $profiles | Add-Member -Force -MemberType NoteProperty -Name ComputerName -value $mailserver.ComputerName
                $profiles | Add-Member -Force -MemberType NoteProperty -Name InstanceName -value $mailserver.InstanceName
                $profiles | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -value $mailserver.SqlInstance

                $profiles | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, Description, ForceDeleteForActiveProfiles, IsBusyProfile
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}