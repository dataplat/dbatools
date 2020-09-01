function Get-DbaDbSharePoint {
    <#
    .SYNOPSIS
        Returns databases that are part of a SharePoint Farm.

    .DESCRIPTION
        Returns databases that are part of a SharePoint Farm, as found in the SharePoint Configuration database.

        By default, this command checks SharePoint_Config. To use an alternate database, use the ConfigDatabase parameter.

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