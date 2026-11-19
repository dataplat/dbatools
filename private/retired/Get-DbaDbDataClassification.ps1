function Get-DbaDbDataClassification {
    <#
    .SYNOPSIS
        Retrieves data classification information for columns in SQL Server databases

    .DESCRIPTION
        Retrieves data classification labels stored as extended properties on table columns. Data classification
        is used to tag sensitive data columns with information type and sensitivity labels, which helps with
        compliance, data governance, and security auditing.

        Classification metadata is stored as four extended properties on each classified column:
        - sys_information_type_id: GUID identifying the information type
        - sys_information_type_name: Human-readable information type name (e.g., "Financial", "Health", "Credentials")
        - sys_sensitivity_label_id: GUID identifying the sensitivity label
        - sys_sensitivity_label_name: Human-readable sensitivity label (e.g., "Public", "General", "Confidential")

        These properties are compatible with Microsoft Information Protection (MIP) labels used by SQL Server
        Data Discovery & Classification in SSMS and Azure SQL Database.

        Requires SQL Server 2005 or later due to use of sys.extended_properties.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory -
        Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to search for data classifications. Only applies when connecting directly via SqlInstance.

    .PARAMETER Schema
        Filters results to columns in the specified schema(s).

    .PARAMETER Table
        Filters results to columns in the specified table(s).

    .PARAMETER Column
        Filters results to the specified column name(s).

    .PARAMETER InputObject
        Accepts database objects piped from Get-DbaDatabase.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataClassification, Classification, Compliance, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2024 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbDataClassification

    .OUTPUTS
        PSCustomObject

        Returns one object per classified column with the following properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name
        - Database: The database name
        - Schema: The schema name of the table
        - Table: The table name
        - Column: The column name
        - InformationTypeId: GUID identifying the information type
        - InformationType: Human-readable information type name
        - SensitivityLabelId: GUID identifying the sensitivity label
        - SensitivityLabel: Human-readable sensitivity label name

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019

        Returns all data classifications across all databases on sql2019.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks

        Returns all data classifications in the AdventureWorks database.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks -Table Customer

        Returns data classifications for columns in the Customer table.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2019 -Database AdventureWorks | Get-DbaDbDataClassification

        Returns all data classifications in AdventureWorks by piping the database object.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks | Where-Object SensitivityLabel -eq "Highly Confidential"

        Returns only columns classified as Highly Confidential in AdventureWorks.
    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [string[]]$Column,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    process {
        if ($SqlInstance) {
            $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database | Where-Object IsAccessible
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent

            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "Data classification requires SQL Server 2005 or later. Skipping $server" -Target $server -Continue
            }

            $sql = "
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    CAST(ep1.value AS NVARCHAR(MAX)) AS InformationTypeId,
    CAST(ep2.value AS NVARCHAR(MAX)) AS InformationType,
    CAST(ep3.value AS NVARCHAR(MAX)) AS SensitivityLabelId,
    CAST(ep4.value AS NVARCHAR(MAX)) AS SensitivityLabel
FROM sys.objects o
INNER JOIN sys.columns c ON o.object_id = c.object_id
LEFT JOIN sys.extended_properties ep1
    ON ep1.major_id = o.object_id AND ep1.minor_id = c.column_id
    AND ep1.name = 'sys_information_type_id' AND ep1.class = 1
LEFT JOIN sys.extended_properties ep2
    ON ep2.major_id = o.object_id AND ep2.minor_id = c.column_id
    AND ep2.name = 'sys_information_type_name' AND ep2.class = 1
LEFT JOIN sys.extended_properties ep3
    ON ep3.major_id = o.object_id AND ep3.minor_id = c.column_id
    AND ep3.name = 'sys_sensitivity_label_id' AND ep3.class = 1
LEFT JOIN sys.extended_properties ep4
    ON ep4.major_id = o.object_id AND ep4.minor_id = c.column_id
    AND ep4.name = 'sys_sensitivity_label_name' AND ep4.class = 1
WHERE o.type = 'U'
  AND (ep1.value IS NOT NULL OR ep2.value IS NOT NULL OR ep3.value IS NOT NULL OR ep4.value IS NOT NULL)
ORDER BY SCHEMA_NAME(o.schema_id), o.name, c.name"

            try {
                $results = $db.Query($sql)
            } catch {
                Stop-Function -Message "Error querying data classifications in $($db.Name) on $server" -ErrorRecord $_ -Target $db -Continue
            }

            foreach ($row in $results) {
                if ($Schema -and $row.SchemaName -notin $Schema) { continue }
                if ($Table -and $row.TableName -notin $Table) { continue }
                if ($Column -and $row.ColumnName -notin $Column) { continue }

                [PSCustomObject]@{
                    ComputerName       = $db.ComputerName
                    InstanceName       = $db.InstanceName
                    SqlInstance        = $db.SqlInstance
                    Database           = $db.Name
                    Schema             = $row.SchemaName
                    Table              = $row.TableName
                    Column             = $row.ColumnName
                    InformationTypeId  = $row.InformationTypeId
                    InformationType    = $row.InformationType
                    SensitivityLabelId = $row.SensitivityLabelId
                    SensitivityLabel   = $row.SensitivityLabel
                    DatabaseObject     = $db
                }
            }
        }
    }
}
