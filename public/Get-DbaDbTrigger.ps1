function Get-DbaDbTrigger {
    <#
    .SYNOPSIS
        Retrieves database-level DDL triggers from SQL Server instances for security auditing and change tracking analysis.

    .DESCRIPTION
        Retrieves all database-level DDL triggers from one or more SQL Server instances. Database triggers fire in response to DDL events like CREATE, ALTER, or DROP statements within a specific database, making them useful for change auditing and security monitoring. This function helps DBAs inventory these triggers for compliance reporting, troubleshooting performance issues, or documenting automated database change tracking mechanisms. Returns trigger details including name, enabled status, and last modification date.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        SqlLogin to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance..

    .PARAMETER Database
        Specifies which databases to scan for DDL triggers. Accepts wildcards for pattern matching.
        Use this when you need to audit triggers in specific databases rather than checking all databases on the instance.

    .PARAMETER ExcludeDatabase
        Excludes specific databases from the trigger scan. Useful for skipping system databases or databases under maintenance.
        Commonly used to exclude tempdb, model, or databases that don't require trigger auditing.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase via pipeline input for targeted trigger analysis.
        Use this when you want to process a pre-filtered set of database objects instead of specifying database names.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Trigger
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbTrigger

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.DatabaseDdlTrigger

        Returns one DatabaseDdlTrigger object per database trigger found on the specified databases. The function enhances the SMO object with additional dbatools properties via Add-Member.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: The name of the database-level DDL trigger
        - IsEnabled: Boolean indicating whether the trigger is enabled
        - DateLastModified: DateTime when the trigger was last modified

        Additional properties available (from SMO DatabaseDdlTrigger object):
        - CreateDate: DateTime when the trigger was created
        - EventSet: The set of DDL events that fire the trigger (CREATE_TABLE, ALTER_TABLE, DROP_TABLE, etc.)
        - ExecutionContext: The execution context of the trigger (Caller, Owner, or specific user)
        - TextHeader: The header portion of the trigger definition
        - TextBody: The body portion of the trigger SQL code
        - Text: The complete T-SQL definition of the trigger
        - Urn: The uniform resource name (URN) uniquely identifying the trigger
        - State: The state of the SMO object (Existing, Creating, Dropping, etc.)

        All properties from the base SMO DatabaseDdlTrigger object are accessible via Select-Object *.

    .EXAMPLE
        PS C:\> Get-DbaDbTrigger -SqlInstance sql2017

        Returns all database triggers

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017 -Database supa | Get-DbaDbTrigger

        Returns all triggers for database supa on sql2017

    .EXAMPLE
        PS C:\> Get-DbaDbTrigger -SqlInstance sql2017 -Database supa

        Returns all triggers for database supa on sql2017

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )

    process {
        foreach ($Instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            try {
                foreach ($trigger in ($db.Triggers)) {
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
                    Add-Member -Force -InputObject $trigger -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
                    Select-DefaultView -InputObject $trigger -Property ComputerName, InstanceName, SqlInstance, Name, IsEnabled, DateLastModified
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
            }
        }
    }
}