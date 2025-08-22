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
        The name of the SharePoint Configuration database. Defaults to SharePoint_Config.

    .PARAMETER InputObject
        Allows piping from Get-DbaDatabase.

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
                $dbName = $db.Query("SELECT [Name] FROM [dbo].[Objects] WHERE id in ('$dbid')").Name
                Get-DbaDatabase -SqlInstance $db.Parent -Database $dbName
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}