function Get-DbaDbMailProfile {
    <#
    .SYNOPSIS
        Retrieves Database Mail profiles and their configuration details from SQL Server instances

    .DESCRIPTION
        Retrieves Database Mail profiles from one or more SQL Server instances, returning detailed configuration information for each profile including ID, name, description, and status properties. This function is essential for auditing Database Mail configurations across your environment, troubleshooting email notification issues, and documenting mail profile setups for compliance or change management. You can target specific profiles by name or exclude certain profiles from the results, making it useful for both broad configuration reviews and focused troubleshooting scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Profile
        Specifies one or more Database Mail profile names to retrieve. Use this when you need to check configuration details for specific profiles rather than reviewing all profiles.
        Accepts exact profile names and is case-sensitive to match SQL Server Database Mail profile naming.

    .PARAMETER ExcludeProfile
        Specifies one or more Database Mail profile names to exclude from the results. Useful when auditing multiple profiles but want to skip certain ones like test or deprecated profiles.
        Helps focus on production profiles during compliance reviews or troubleshooting scenarios.

    .PARAMETER InputObject
        Accepts Database Mail server objects from Get-DbaDbMail cmdlet through the pipeline. This allows you to chain commands when working with multiple SQL instances.
        Eliminates the need to specify SqlInstance when you already have Database Mail objects from a previous command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Mail.MailProfile

        Returns one or more Database Mail profile objects from the target SQL Server instance(s). Each profile object includes configuration details for organizing mail accounts used for notifications and alerts.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - ID: The unique identifier (int) for the Database Mail profile within the instance
        - Name: The name of the Database Mail profile
        - Description: Text description of the profile's purpose or intended use
        - ForceDeleteForActiveProfiles: Boolean indicating if the profile will be forcefully deleted even if actively used
        - IsBusyProfile: Boolean indicating if the profile is currently busy processing mail messages

        Additional properties available (from SMO MailProfile object):
        - Parent: Reference to the parent SqlMail object
        - Properties: Collection of property objects for the profile
        - State: Current state of the profile object (Existing, Creating, Deleting)
        - Urn: The unified resource name (URN) for the object
        - Uid: Unique identifier for the profile
        - MailAccountMemberships: Collection of mail accounts associated with this profile
        - LastModificationTime: DateTime when the profile was last modified (if available)

        Use Select-Object * to access all available properties if needed.

    .NOTES
        Tags: Mail, DbMail, Email
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
        PS C:\> $servers = "sql2014", "sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaDbMail | Get-DbaDbMailProfile

        Returns the DBMail profiles for "sql2014", "sql2016" and "sqlcluster\sharepoint"

    .EXAMPLE
        PS C:\> $servers = "sql2014", "sql2016", "sqlcluster\sharepoint"
        PS C:\> Get-DbaDbMailProfile -SqlInstance $servers

        Returns the DBMail profiles for "sql2014", "sql2016" and "sqlcluster\sharepoint"

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
            $InputObject += Get-DbaDbMail -SqlInstance $instance -SqlCredential $SqlCredential
        }

        if (-not $InputObject) {
            Stop-Function -Message "No servers to process"
            return
        }

        foreach ($mailserver in $InputObject) {
            try {
                $profiles = $mailserver.Profiles

                if ($Profile) {
                    $profiles = $profiles | Where-Object Name -In $Profile
                }

                If ($ExcludeProfile) {
                    $profiles = $profiles | Where-Object Name -NotIn $ExcludeProfile

                }

                $profiles | Add-Member -Force -MemberType NoteProperty -Name ComputerName -Value $mailserver.ComputerName
                $profiles | Add-Member -Force -MemberType NoteProperty -Name InstanceName -Value $mailserver.InstanceName
                $profiles | Add-Member -Force -MemberType NoteProperty -Name SqlInstance -Value $mailserver.SqlInstance

                $profiles | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, ID, Name, Description, ForceDeleteForActiveProfiles, IsBusyProfile
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}