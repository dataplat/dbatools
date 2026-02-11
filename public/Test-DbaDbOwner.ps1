function Test-DbaDbOwner {
    <#
    .SYNOPSIS
        Identifies databases with incorrect ownership for security compliance and best practice enforcement.

    .DESCRIPTION
        This function compares the current owner of each database against a target login and returns only databases that do NOT match the expected owner. By default, it checks against 'sa' (or the renamed sysadmin account if 'sa' was changed), but you can specify any valid login.

        This addresses a common security compliance requirement where databases should be owned by a specific account rather than individual user accounts. Mismatched ownership can cause issues with scheduled jobs, maintenance plans, and security policies.

        The function automatically detects if the 'sa' account was renamed and uses the actual sysadmin login name. It returns detailed information including current owner, target owner, and ownership status for easy identification of databases requiring ownership changes.

        Best Practice reference: http://weblogs.sqlteam.com/dang/archive/2008/01/13/Database-Owner-Troubles.aspx

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to check for ownership compliance. Accepts wildcards for pattern matching.
        Use this when you need to audit ownership for specific databases rather than all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during the ownership compliance check. Accepts wildcards for pattern matching.
        Useful for excluding system databases or databases with intentionally different ownership from standard policy.

    .PARAMETER TargetLogin
        Specifies the expected database owner login for compliance checking. Defaults to 'sa' or the renamed sysadmin account if 'sa' was changed.
        Use this to enforce organizational standards where databases should be owned by a service account or specific login rather than individual users.

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase for ownership verification.
        Use this to check ownership on a pre-filtered set of databases or when chaining with other database operations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Owner, DbOwner
        Author: Michael Fal (@Mike_Fal), mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        PSCustomObject

        Returns one object per database checked for ownership compliance. The OwnerMatch property indicates whether the current owner matches the target owner.

        Default display properties (via Select-DefaultView -ExcludeProperty Server):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: The name of the database being checked
        - DBState: The current database state (Online, Offline, Restoring, etc.)
        - CurrentOwner: The login name of the current database owner
        - TargetOwner: The login name of the expected database owner (the compliance target)
        - OwnerMatch: Boolean indicating whether the current owner matches the target owner

        Additional properties available (excluded from default display):
        - Server: The full SQL Server instance name (same as SqlInstance, excluded from default view)

    .LINK
        https://dbatools.io/Test-DbaDbOwner

    .EXAMPLE
        PS C:\> Test-DbaDbOwner -SqlInstance localhost

        Returns all databases where the owner does not match 'sa'.

    .EXAMPLE
        PS C:\> Test-DbaDbOwner -SqlInstance localhost -TargetLogin 'DOMAIN\account'

        Returns all databases where the owner does not match 'DOMAIN\account'.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -OnlyAccessible | Test-DbaDbOwner

        Gets only accessible databases and checks where the owner does not match 'sa'.
    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [string]$TargetLogin,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Switch]$EnableException
    )
    process {
        if (-not $InputObject -and -not $Sqlinstance) {
            Stop-Function -Message 'You must specify a $SqlInstance parameter'
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        #for each database, create custom object for return set.
        foreach ($db in $InputObject) {
            $server = $db.Parent

            # dynamic sa name for orgs who have changed their sa name
            if (Test-Bound -ParameterName TargetLogin -Not) {
                $TargetLogin = ($server.logins | Where-Object {
                        $_.id -eq 1
                    }).Name
            }

            #Validate login
            if (($server.Logins.Name) -notmatch [Regex]::Escape($TargetLogin)) {
                Write-Message -Level Verbose -Message "$TargetLogin is not a login on $instance" -Target $instance
            }

            Write-Message -Level Verbose -Message "Checking $db"
            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Server       = $server.DomainInstanceName
                Database     = $db.Name
                DBState      = $db.Status
                CurrentOwner = $db.Owner
                TargetOwner  = $TargetLogin
                OwnerMatch   = ($db.owner -eq $TargetLogin)
            } | Select-DefaultView -ExcludeProperty Server
        }
    }
}