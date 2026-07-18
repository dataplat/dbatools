function Set-DbaDbDataClassification {
    <#
    .SYNOPSIS
        Adds or updates data classification labels on SQL Server table columns

    .DESCRIPTION
        Creates or updates data classification metadata on table columns by setting four extended properties:
        - sys_information_type_id: GUID identifying the information type
        - sys_information_type_name: Human-readable information type name
        - sys_sensitivity_label_id: GUID identifying the sensitivity label
        - sys_sensitivity_label_name: Human-readable sensitivity label name

        This command performs an upsert: if a classification property already exists on the column it will be
        updated, otherwise it will be created. You can update only the information type, only the sensitivity
        label, or both at once.

        Built-in GUID mappings are provided for well-known Microsoft Information Protection types and labels.
        If InformationType or SensitivityLabel matches a known value, the corresponding ID will be set
        automatically. Custom values are also supported by providing both the name and ID explicitly.

        Known Information Types: Networking, Contact Info, Credentials, Credit Card, Banking, Financial,
        Other, Name, National ID, SSN, Health, Date Of Birth

        Known Sensitivity Labels: Public, General, Confidential, Confidential - GDPR, Highly Confidential,
        Highly Confidential - GDPR

        Requires SQL Server 2005 or later due to use of sp_addextendedproperty / sp_updateextendedproperty.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory -
        Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which database contains the table to classify.

    .PARAMETER Schema
        The schema of the table to classify. Defaults to "dbo".

    .PARAMETER Table
        The table containing the column to classify.

    .PARAMETER Column
        The column to classify.

    .PARAMETER InformationType
        The information type name to assign. If this matches a known MIP type, InformationTypeId will be
        populated automatically. For custom types, provide InformationTypeId explicitly.

    .PARAMETER InformationTypeId
        The GUID for the information type. Optional when InformationType matches a known MIP type.

    .PARAMETER SensitivityLabel
        The sensitivity label name to assign. If this matches a known MIP label, SensitivityLabelId will be
        populated automatically. For custom labels, provide SensitivityLabelId explicitly.

    .PARAMETER SensitivityLabelId
        The GUID for the sensitivity label. Optional when SensitivityLabel matches a known MIP label.

    .PARAMETER InputObject
        Accepts classification objects piped from Get-DbaDbDataClassification. When used, the Schema, Table,
        Column, and database context are taken from the piped object.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        https://dbatools.io/Set-DbaDbDataClassification

    .OUTPUTS
        PSCustomObject

        Returns the updated classification object with the same properties as Get-DbaDbDataClassification.

    .EXAMPLE
        PS C:\> Set-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks -Table Customer -Column EmailAddress -InformationType "Contact Info" -SensitivityLabel "Confidential"

        Sets the classification for the EmailAddress column in the Customer table of AdventureWorks.
        The InformationTypeId and SensitivityLabelId are automatically populated from the built-in mapping.

    .EXAMPLE
        PS C:\> Set-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks -Schema HumanResources -Table Employee -Column NationalIDNumber -InformationType "National ID" -SensitivityLabel "Highly Confidential"

        Sets classification for a column in a non-dbo schema.

    .EXAMPLE
        PS C:\> Get-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks | Set-DbaDbDataClassification -SensitivityLabel "Highly Confidential"

        Updates the sensitivity label to "Highly Confidential" for all classified columns in AdventureWorks,
        keeping the information type unchanged.

    .EXAMPLE
        PS C:\> Set-DbaDbDataClassification -SqlInstance sql2019 -Database AdventureWorks -Table Orders -Column CreditCardNumber -InformationType "Credit Card" -InformationTypeId "D22FA6E9-5EE4-3BDE-4C2B-A409604C4646" -SensitivityLabel "Highly Confidential - GDPR" -Confirm:$false

        Sets a classification with an explicit GUID for the information type.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string]$Schema = "dbo",
        [string]$Table,
        [string]$Column,
        [string]$InformationType,
        [string]$InformationTypeId,
        [string]$SensitivityLabel,
        [string]$SensitivityLabelId,
        [parameter(ValueFromPipeline)]
        [psobject[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        # Built-in GUID mappings for Microsoft Information Protection types
        $informationTypeMap = @{
            "Networking"    = "B40AD280-0F6A-6CA8-11BA-2F1A08651FCF"
            "Contact Info"  = "5C503E21-22C6-81FA-620B-F369B8EC38D1"
            "Credentials"   = "C64ABA7B-3A3E-95B6-535D-3BC535DA5A59"
            "Credit Card"   = "D22FA6E9-5EE4-3BDE-4C2B-A409604C4646"
            "Banking"       = "8A462631-4130-0A31-9A52-C6A9CA125F92"
            "Financial"     = "C44193E1-0E58-4B2A-9001-F7D6E7BC1373"
            "Other"         = "9C5B4809-0CCC-0637-6547-91A6F8BB609D"
            "Name"          = "57845286-7598-22F5-9659-15B24AEB125E"
            "National ID"   = "6F5A11A7-08B1-19C3-59E5-8C89CF4F8444"
            "SSN"           = "D936EC2C-04A4-9CF7-44C2-378A96456C61"
            "Health"        = "6E2C5B18-97CF-3073-27AB-F12F87493DA7"
            "Date Of Birth" = "3DE7CC52-710D-4E96-7E20-4D5188D2590C"
        }

        # Built-in GUID mappings for Microsoft Information Protection sensitivity labels
        $sensitivityLabelMap = @{
            "Public"                     = "1866CA45-1973-4C28-9D12-04D407F147AD"
            "General"                    = "684A0DB2-D514-49D8-8C0C-DF84A7B083EB"
            "Confidential"               = "331F0B13-76B5-2F1B-A77B-DEF5A73C73C2"
            "Confidential - GDPR"        = "989ADC05-3F3F-0588-A635-F475B994915B"
            "Highly Confidential"        = "B82CE05B-60A9-4CF3-8A8A-D6A0BB76E903"
            "Highly Confidential - GDPR" = "3302AE7F-B8AC-46BC-97F8-378828781EFD"
        }

        # Resolve IDs from built-in mappings when not explicitly provided
        if ($InformationType -and -not $InformationTypeId -and $informationTypeMap.ContainsKey($InformationType)) {
            $InformationTypeId = $informationTypeMap[$InformationType]
        }

        if ($SensitivityLabel -and -not $SensitivityLabelId -and $sensitivityLabelMap.ContainsKey($SensitivityLabel)) {
            $SensitivityLabelId = $sensitivityLabelMap[$SensitivityLabel]
        }

        # Upsert a single extended property on a column
        function Invoke-UpsertExtendedProperty {
            param (
                [Microsoft.SqlServer.Management.Smo.Database]$Db,
                [string]$PropName,
                [string]$PropValue,
                [string]$SchemaName,
                [string]$TableName,
                [string]$ColumnName
            )
            $escapedSchema   = $SchemaName.Replace("'", "''")
            $escapedTable    = $TableName.Replace("'", "''")
            $escapedColumn   = $ColumnName.Replace("'", "''")
            $escapedPropName = $PropName.Replace("'", "''")
            $escapedValue    = $PropValue.Replace("'", "''")

            $checkSql = "
SELECT COUNT(1) AS PropExists
FROM sys.extended_properties ep
INNER JOIN sys.objects o ON ep.major_id = o.object_id
INNER JOIN sys.columns c ON o.object_id = c.object_id AND ep.minor_id = c.column_id
WHERE SCHEMA_NAME(o.schema_id) = '$escapedSchema'
  AND o.name = '$escapedTable'
  AND c.name = '$escapedColumn'
  AND ep.name = '$escapedPropName'
  AND ep.class = 1"

            $exists = $Db.Query($checkSql).PropExists

            if ($exists -gt 0) {
                $Db.Query("EXEC sys.sp_updateextendedproperty @name = N'$escapedPropName', @value = N'$escapedValue', @level0type = N'SCHEMA', @level0name = N'$escapedSchema', @level1type = N'TABLE', @level1name = N'$escapedTable', @level2type = N'COLUMN', @level2name = N'$escapedColumn'")
            } else {
                $Db.Query("EXEC sys.sp_addextendedproperty @name = N'$escapedPropName', @value = N'$escapedValue', @level0type = N'SCHEMA', @level0name = N'$escapedSchema', @level1type = N'TABLE', @level1name = N'$escapedTable', @level2type = N'COLUMN', @level2name = N'$escapedColumn'")
            }
        }
    }
    process {
        if ($SqlInstance) {
            if (-not $Table -or -not $Column) {
                Stop-Function -Message "Table and Column must be specified when using SqlInstance" -EnableException $EnableException
                return
            }
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Failure connecting to $instance" -ErrorRecord $_ -Target $instance -Continue
                    continue
                }
                foreach ($dbName in $Database) {
                    $db = $server.Databases[$dbName]
                    if (-not $db) {
                        Stop-Function -Message "Database '$dbName' not found on $instance" -Target $instance -Continue
                        continue
                    }

                    $target = "[$Schema].[$Table].[$Column] in $dbName on $instance"
                    if (-not $Pscmdlet.ShouldProcess($target, "Setting data classification")) { continue }

                    try {
                        if ($InformationType) {
                            $splatInfo = @{
                                Db         = $db
                                PropName   = "sys_information_type_name"
                                PropValue  = $InformationType
                                SchemaName = $Schema
                                TableName  = $Table
                                ColumnName = $Column
                            }
                            $null = Invoke-UpsertExtendedProperty @splatInfo
                            $splatInfoId = @{
                                Db         = $db
                                PropName   = "sys_information_type_id"
                                PropValue  = "$InformationTypeId"
                                SchemaName = $Schema
                                TableName  = $Table
                                ColumnName = $Column
                            }
                            $null = Invoke-UpsertExtendedProperty @splatInfoId
                        }
                        if ($SensitivityLabel) {
                            $splatLabel = @{
                                Db         = $db
                                PropName   = "sys_sensitivity_label_name"
                                PropValue  = $SensitivityLabel
                                SchemaName = $Schema
                                TableName  = $Table
                                ColumnName = $Column
                            }
                            $null = Invoke-UpsertExtendedProperty @splatLabel
                            $splatLabelId = @{
                                Db         = $db
                                PropName   = "sys_sensitivity_label_id"
                                PropValue  = "$SensitivityLabelId"
                                SchemaName = $Schema
                                TableName  = $Table
                                ColumnName = $Column
                            }
                            $null = Invoke-UpsertExtendedProperty @splatLabelId
                        }
                    } catch {
                        Stop-Function -Message "Failure setting data classification on $target" -ErrorRecord $_ -Target $db -Continue
                        continue
                    }

                    Get-DbaDbDataClassification -InputObject $db -Schema $Schema -Table $Table -Column $Column
                }
            }
            return
        }

        foreach ($classObj in $InputObject) {
            $db = $classObj.DatabaseObject
            if (-not $db) {
                Stop-Function -Message "No database object found in input. Pipe from Get-DbaDbDataClassification or use -SqlInstance/-Database/-Table/-Column parameters." -Continue
                continue
            }

            $server = $db.Parent
            $schemaName = $classObj.Schema
            $tableName = $classObj.Table
            $columnName = $classObj.Column
            $target = "[$schemaName].[$tableName].[$columnName] in $($db.Name) on $server"

            if (-not $Pscmdlet.ShouldProcess($target, "Setting data classification")) { continue }

            try {
                if ($InformationType) {
                    $splatInfo = @{
                        Db         = $db
                        PropName   = "sys_information_type_name"
                        PropValue  = $InformationType
                        SchemaName = $schemaName
                        TableName  = $tableName
                        ColumnName = $columnName
                    }
                    $null = Invoke-UpsertExtendedProperty @splatInfo
                    $splatInfoId = @{
                        Db         = $db
                        PropName   = "sys_information_type_id"
                        PropValue  = "$InformationTypeId"
                        SchemaName = $schemaName
                        TableName  = $tableName
                        ColumnName = $columnName
                    }
                    $null = Invoke-UpsertExtendedProperty @splatInfoId
                }
                if ($SensitivityLabel) {
                    $splatLabel = @{
                        Db         = $db
                        PropName   = "sys_sensitivity_label_name"
                        PropValue  = $SensitivityLabel
                        SchemaName = $schemaName
                        TableName  = $tableName
                        ColumnName = $columnName
                    }
                    $null = Invoke-UpsertExtendedProperty @splatLabel
                    $splatLabelId = @{
                        Db         = $db
                        PropName   = "sys_sensitivity_label_id"
                        PropValue  = "$SensitivityLabelId"
                        SchemaName = $schemaName
                        TableName  = $tableName
                        ColumnName = $columnName
                    }
                    $null = Invoke-UpsertExtendedProperty @splatLabelId
                }
            } catch {
                Stop-Function -Message "Failure setting data classification on $target" -ErrorRecord $_ -Target $db -Continue
                continue
            }

            Get-DbaDbDataClassification -InputObject $db -Schema $schemaName -Table $tableName -Column $columnName
        }
    }
}
