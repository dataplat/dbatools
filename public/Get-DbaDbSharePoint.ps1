function Get-DbaDbSharePoint {
    <#
    .SYNOPSIS
        Identifies all databases belonging to a SharePoint farm by querying the SharePoint Configuration database.

    .DESCRIPTION
        Discovers and returns database objects for all databases that are part of a SharePoint farm by querying the SharePoint Configuration database's internal tables and stored procedures. This helps DBAs identify which databases on their SQL Server instance are actively used by SharePoint, eliminating guesswork when planning maintenance, migrations, or troubleshooting SharePoint connectivity issues.

        The function queries the SharePoint Configuration database to find registered SharePoint databases using SharePoint's internal proc_getObjectsByBaseClass stored procedure and Objects table. By default, this command checks SharePoint_Config. To use an alternate configuration database, use the ConfigDatabase parameter.

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ConfigDatabase
        Specifies the name of the SharePoint Configuration database to query for farm database information. Defaults to SharePoint_Config.
        Use this when your SharePoint farm uses a non-standard configuration database name, such as SharePoint_Config_2016 or when managing multiple SharePoint versions on the same SQL instance.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase to directly analyze specific SharePoint Configuration databases.
        Use this when you want to target a specific configuration database without connecting to the SQL instance again, or when working with multiple SharePoint farms across different instances.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SharePoint
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSharePoint

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster

        Returns databases that are part of a SharePoint Farm, as found in SharePoint_Config on sqlcluster

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlcluster -Database SharePoint_Config_2016 | Get-DbaDbSharePoint

        Returns databases that are part of a SharePoint Farm, as found in SharePoint_Config_2016 on sqlcluster

    .OUTPUTS
        Microsoft.SqlServer.Management.Smo.Database

        Returns one SMO Database object for each SharePoint database found in the SharePoint farm. Output is produced by Get-DbaDatabase, which sets default display properties via Select-DefaultView.

        Default display properties (via Get-DbaDatabase / Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Name: Database name
        - Status: Current database status
        - IsAccessible: Boolean indicating if the database is currently accessible
        - RecoveryModel: Database recovery model (Full, Simple, BulkLogged)
        - LogReuseWaitStatus: Status of transaction log reuse
        - SizeMB: Database size in megabytes (aliased from Size)
        - Compatibility: Database compatibility level (aliased from CompatibilityLevel)
        - Collation: Database collation setting
        - Owner: Database owner login name
        - Encrypted: Boolean indicating if TDE is enabled (aliased from EncryptionEnabled)
        - LastFullBackup: DateTime of the most recent full backup (aliased from LastBackupDate)
        - LastDiffBackup: DateTime of the most recent differential backup (aliased from LastDifferentialBackupDate)
        - LastLogBackup: DateTime of the most recent transaction log backup (aliased from LastLogBackupDate)

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$ConfigDatabase = "SharePoint_Config",
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $ConfigDatabase
        }

        foreach ($db in $InputObject) {
            try {
                $guid = $db.Query("SELECT Id FROM Classes WHERE FullName LIKE 'Microsoft.SharePoint.Administration.SPDatabase,%'").Id.Guid
                $dbid = $db.Query("[dbo].[proc_getObjectsByBaseClass] @BaseClassId = '$guid', @ParentId = NULL").Id.Guid -join "', '"
                $dbName = $db.Query("SELECT [Name] FROM [dbo].[Objects] WHERE Id IN ('$dbid')").Name
                Get-DbaDatabase -SqlInstance $db.Parent -Database $dbName
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}