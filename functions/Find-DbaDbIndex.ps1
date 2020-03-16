function Find-DbaDbIndex
{ 
    <# 
    .SYNOPSIS 
        Helps locate indexes in non-heap tables based on SchemaName/TableName/IndexName/ColumnName and get the index details

    .DESCRIPTION 
    
        Given a list of SQL Instances, searches all/specific databases in each instance using exact/like matching for
            a matching Schema name (optional) 
            a matching Table name (optional) 
            a matching Index name (optional)
            a matching Column name in index columns (optional)
    
        Returns indexes matching all of the above criteria

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input
    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
        For MFA support, please use Connect-DbaInstance.
    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.
    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server
    .PARAMETER SchemaName
        If you are looking in a specific schema whose indexes need to be returned, provide the name of the schema.
        If no schema is provided, looks at all schemas
        If the schema exists in multiple databases, all of them would qualify unless limited by Database parameter
    .PARAMETER SchemaNameMatchType
        Takes one of two values 'Exact' or 'Like'
        When 'Exact' is specified, does an exact match on SchemaName 
        When 'Like' is specified, a LIKE '%SchemaName%' type match
    .PARAMETER TableName
        If you are looking in a specific table whose indexes need to be returned, provide the name of the table.
        If no table is provided, looks at all tables
        If the table name exists in multiple schemas, all of them would qualify
    .PARAMETER TableNameMatchType
        Takes one of two values 'Exact' or 'Like'
        When 'Exact' is specified, does an exact match on TableName 
        When 'Like' is specified, a LIKE '%TableName%' type match
    .PARAMETER IndexName
        If you are looking in a specific index by name that needs to be returned, provide the name of the index.
        If no index name is provided, looks at all indexes
        If the index name exists in multiple tables, all of them would qualify
    .PARAMETER IndexNameMatchType
        Takes one of two values 'Exact' or 'Like'
        When 'Exact' is specified, does an exact match on IndexName 
        When 'Like' is specified, a LIKE '%IndexName%' type match
    .PARAMETER IndexColumnName
        If you are looking in a specific column name used in indexes that need to be returned, provide the name of the column.
        If no column name is provided, looks at all columns
        If the column name exists in multiple tables, all of them would qualify unless limited by SchemaName or TableName parameters
    .PARAMETER IndexColumnNameMatchType
        Takes one of two values 'Exact' or 'Like'
        When 'Exact' is specified, does an exact match on ColumnName 
        When 'Like' is specified, a LIKE '%ColumnName%' type match
    .PARAMETER IncludeSystemDatabases
        If this switch is enabled, the output will include matching index defintions from system databases
    .PARAMETER IncludeDataTypes
        If this switch is enabled, the output will include the data type of each column that makes up a part of the index definition 
        (key and include columns).
    .PARAMETER IncludeFragmentation
        If this switch is enabled, the output will include fragmentation information.       
    .PARAMETER IncludeStats
        If this switch is enabled, statistics as well as indexes will be returned in the output (statistics information such as the 
        StatsRowMods will always be returned for indexes).
    .PARAMETER Raw
        If this switch is enabled, results may be less user-readable but more suitable for processing by other code.
    
    .OUTPUTS 
        Matching indexes. Output depends on input parameters.
    
        Output is the same as what is returned by function Get-DbaHelpIndex 
            and depends on input parameters (e.g., IncludeStats, IncludeFragmentation etc.)
    
    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('MyDB')
        [string] $indexColumnName = 'SECURITY_ID'
        [string] $indexColumnNameMatchType = 'LIKE'    
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -IndexColumnName $indexColumnName `
                    -IndexColumnNameMatchType $indexColumnNameMatchType

        This example returns all indexes in all schemas, all tables of given SQL instances, database
            with any index having the given column name like SECURITY_ID.
            E.g., SECURITY_ID, HDM_SECURITY_ID, SECURITY_ID_KEY, AUDIT_SECURITY_ID etc.

    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('MyDB')
        [string] $schemaName = 'AUDIT'
        [string] $schemaNameMatchType = 'AUDIT'
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -SchemaName $schemaName `
                    -SchemaNameMatchType $schemaNameMatchType

        This example returns all indexes in all tables of given SQL instances, databases
            in all tables with SchemaName AUDIT

    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('MyDB')
        [string] $tableName = 'SECURITY_CODE'
        [string] $tableNameMatchType = 'LIKE'
        [string] $indexColumnName = 'SECURITY_ID'
        [string] $indexColumnNameMatchType = 'EXACT'
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -TableName $tableName `
                    -TableNameMatchType $tableNameMatchType `
                    -IndexColumnName $indexColumnName `
                    -IndexColumnNameMatchType $indexColumnNameMatchType

        This example searches all given instances, databases, for table names like SECURITY_CODE
            returns all matchng indexes in those tables with indexes on column SECURITY_ID
        In this case, the table names could be SECURITY_CODE, HDM_SECURITY_CODE, SECURITY_CODE_AUDIT etc
            that have a column named SECURITY_ID which is part of the returned index

    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @()
        [string] $tableName = 'SECURITY_CODE'
        [string] $tableNameMatchType = 'LIKE'
        [string] $indexName = 'SECURITY'
        [string] $indexNameMatchType = 'LIKE'
        [string] $indexColumnName = 'SECURITY_ID'
        [string] $indexColumnNameMatchType = 'LIKE'
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -TableName $tableName `
                    -TableNameMatchType $tableNameMatchType `
                    -IndexName $indexName `
                    -IndexNameMatchType $indexNameMatchType `
                    -IndexColumnName $indexColumnName `
                    -IndexColumnNameMatchType $indexColumnNameMatchType
    
        This example searches all given instances, all databases, for table names like SECURITY_CODE
            returns all matchng indexes in those tables with indexes on column SECURITY_ID
        In this case, the table names could be SECURITY_CODE, HDM_SECURITY_CODE, SECURITY_CODE_AUDIT etc
            with an index named like SECURITY (could be PK_SECURITY, SECURITY_IDX01 etc)
            that have a column named SECURITY_ID which is part of the returned index

    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('MyDB')    
        [string] $tableName = 'SECURITY_CODE'
        [string] $tableNameMatchType = 'LIKE'
        [string] $indexColumnName = 'SECURITY_ID'
        [string] $indexColumnNameMatchType = 'EXACT'
        [bool] $includeStats = $false
        [bool] $includeFragmentation = $false
        [bool] $includeDataTypes = $true

        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -TableName $tableName `
                    -TableNameMatchType $tableNameMatchType `
                    -IndexColumnName $indexColumnName `
                    -IndexColumnNameMatchType $indexColumnNameMatchType `
                    -IncludeStats: $includeStats `
                    -IncludeFragmentation: $includeFragmentation `
                    -IncludeDataTypes: $includeDataTypes `
                    -Verbose | ogv

        This example searches all given instances, databases, for table names like SECURITY_CODE
            returns all matchng indexes in those tables with indexes on column SECURITY_ID
        In this case, the table names could be SECURITY_CODE, HDM_SECURITY_CODE, SECURITY_CODE_AUDIT etc
            that have a column named SECURITY_ID which is part of the returned index
            but does not include index statistics and fragmentation information in the returned data
        This also includes the datatype of the columns like "SECURITY_ID (bigint)" in KeyColumns property

    .EXAMPLE 
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('master', 'msdb', 'tempdb', 'model')
        [string] $indexName = 'sys'
        [string] $indexNameMatchType = 'LIKE'
        [bool] $includeSystemDatabases = $true
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -IndexName $indexName `
                    -IndexNameMatchType $indexNameMatchType `
                    -IncludeSystemDatabases: $includeSystemDatabases

        This example finds all indexes in the system databases master, msdb, tempdb and model
            for indexes which contain the name "sys" with IncludeSystemDatabases switch set to $true

    .EXAMPLE 
        #SQL Server setup for testing
        /*
        SELECT * INTO #dbatoolsObjects FROM master.sys.objects
        CREATE NONCLUSTERED	INDEX ix_dbatoolsObjects_name ON #dbatoolsObjects (name);
        CREATE NONCLUSTERED	INDEX ix_dbatoolsObjects_object_id ON #dbatoolsObjects (object_id);
        */
        
        [DbaInstanceParameter[]] $sqlInstance = @('MySQLHost1\Instance1', 'MySQLHost2', 'MySQLHost3\Instance1')
        [string[]] $database = @('tempdb')
        [bool] $includeSystemDatabases = $true
        Find-DbaDbIndex `
                    -SqlInstance $sqlInstance `
                    -Database $database `
                    -IncludeSystemDatabases: $includeSystemDatabases

        This example finds all tables with indexes in the tempdb right now (may be surprising or insightful)

    .NOTES
        Tags: Table, Index, Column
        Author: Jana Sattainathan (@SQLJana), http://sqljana.wordpress.com
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaDbIndex
        https://sqljana.wordpress.com/2020/03/13/powershell-sql-server-search-find-indexes-by-schemaname-tablename-indexname-or-columnname-across-instances-dbs/
             
    #>
    [CmdletBinding()] 
    param
    ( 	 
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,        

        [PSCredential]$SqlCredential,
        
        [object[]]$Database,

        [object[]]$ExcludeDatabase,

        [string]$SchemaName,

        [ValidateSet('Exact','Like', ignorecase=$true)]
        [string]$SchemaNameMatchType = 'Exact',

        [string]$TableName,

        [ValidateSet('Exact','Like', ignorecase=$true)]
        [string]$TableNameMatchType = 'Exact',

        [string]$IndexName,

        [ValidateSet('Exact','Like', ignorecase=$true)]
        [string]$IndexNameMatchType = 'Exact',

        [string]$IndexColumnName,

        [ValidateSet('Exact','Like', ignorecase=$true)]
        [string]$IndexColumnNameMatchType = 'Exact',

        [switch]$IncludeSystemDatabases = $false,
        
        [switch]$IncludeStats,

        [switch]$IncludeDataTypes,

        [switch]$Raw,

        [switch]$IncludeFragmentation,

        [switch]$EnableException
    )


    [string] $fn = $MyInvocation.MyCommand
    [string] $stepName = ''
    [string] $message = ''

    [object[]] $dbs = @()
    [string] $schemaMatchString = ""
    [string] $tableMatchString = ""
    [string] $indexMatchString = ""
    [string] $indexColumnMatchString = ""

    $stepName = "Validate parameters"
    #--------------------------------------------
    Write-Message -Level Verbose -Message $stepName
    

    if (($Database.Count -eq 0) `
        -and ($SchemaName.Trim().Length -eq 0) `
        -and ($TableName.Trim().Length -eq 0) `
        -and ($IndexName.Trim().Length -eq 0) `
        -and ($IndexColumnName.Trim().Length -eq 0)
        )
    {
        $message = "Since no criteria is specified, all non-heap table indexes of all databases in all given instances will be retrieved!"

        Write-Message -Level Warning -Message $message        
    }

    $stepName = "Loop through the SQL Instances"
    #--------------------------------------------        
    Write-Message -Level Verbose -Message $stepName        

    foreach($instance IN $SqlInstance)
    {

        $stepName = "Establish connection to SQL Instance [$instance]"
        #--------------------------------------------
        Write-Message -Level Verbose -Message $stepName
            
        try 
        {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } 
        catch 
        {
            $message = "Error occurred while establishing connection to $instance"

            Stop-Function -Message $message -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        $stepName = "Get the list of all qualifying databases"
        #--------------------------------------------
        Write-Message -Level Verbose -Message $stepName
            
        #Use IsAccessible instead of Status -eq 'normal' because databases that are on readable secondaries for AG or mirroring replicas will cause errors to be thrown
        if ($IncludeSystemDatabases) 
        {
            $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true }
        } 
        else 
        {
            $dbs = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and $_.IsSystemObject -eq $false }
        }


        if ($Database) 
        {
            $dbs = $dbs | Where-Object Name -In $Database
        }

        if ($ExcludeDatabase) 
        {
            $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
        }


        if ($dbs.Count -le 0) 
        {
            $message = "No databases qualified in [$instance].[$($db.Name)]"

            Write-Message -Level Warning -Message $message
        }
        else
        {
            $stepName = "Loop through all databases in [$instance]"
            #--------------------------------------------        
            Write-Message -Level Verbose -Message $stepName

            foreach($db in $dbs)
            {
                $stepName = "Get the qualifying tables/indexes in [$instance].[$db] for matching schema/table/index/column names"
                #--------------------------------------------        
                Write-Message -Level Verbose -Message $stepName

                #If nothing is specified for SchemaName, we want to match all schemas
                $schemaMatchString = "%"
                if($SchemaName.Trim().Length -gt 0)
                {
                    $schemaMatchString = $SchemaName.ToUpper().Trim().Replace("'","")  #SQLInjection protection

                    if (-not ($SchemaNameMatchType.ToUpper() -eq 'EXACT'))
                    {
                        $schemaMatchString = "%$schemaMatchString%"
                    }
                }

                #If nothing is specified for TableName, we want to match all tables
                $tableMatchString = "%"
                if($TableName.Trim().Length -gt 0)
                {
                    $tableMatchString = $TableName.ToUpper().Trim().Replace("'","")  #SQLInjection protection

                    if (-not ($TableNameMatchType.ToUpper() -eq 'EXACT'))
                    {
                        $tableMatchString = "%$tableMatchString%"
                    }
                }
                
                #If nothing is specified for IndexName, we want to match all indexs
                $indexMatchString = "%"
                if($IndexName.Trim().Length -gt 0)
                {
                    $indexMatchString = $IndexName.ToUpper().Trim().Replace("'","")  #SQLInjection protection

                    if (-not ($IndexNameMatchType.ToUpper() -eq 'EXACT'))
                    {
                        $indexMatchString = "%$indexMatchString%"
                    }
                }
                
                #If nothing is specified for IndexColumnName, we want to match all indexIndexColumnNames
                $indexColumnNameMatchString = "%"
                if($IndexColumnName.Trim().Length -gt 0)
                {
                    $indexColumnNameMatchString = $IndexColumnName.ToUpper().Trim().Replace("'","")  #SQLInjection protection

                    if (-not ($IndexColumnNameMatchType.ToUpper() -eq 'EXACT'))
                    {
                        $indexColumnNameMatchString = "%$indexColumnNameMatchString%"
                    }
                }

                #https://stackoverflow.com/questions/765867/list-of-all-index-index-columns-in-sql-server-db/765892
                $sql  = "SELECT DISTINCT 
                                sqlInst = @@SERVERNAME,
                                DBName = DB_NAME(),
                                IndexName = I.name, --QUOTENAME(I.name), 
                                SchemaName = SCHEMA_NAME(T.[schema_id]),
                                TableName = T.[name],
                                TableDotSchemaName = QUOTENAME(SCHEMA_NAME(T.[schema_id])) +  N'.' + QUOTENAME(T.name), 
                                IsPrimaryKey = I.is_primary_key,
                                IsUnique = I.is_unique,
                                IsUniqueConstraint = I.is_unique_constraint,
                                IsMSShipped = T.is_ms_shipped
                        FROM sys.indexes AS I
                        INNER JOIN sys.tables AS T
                                ON I.[object_id] = T.[object_id]
                        INNER JOIN sys.index_columns IC 
		                        ON  I.object_id = IC.object_id 
			                        AND I.index_id = IC.index_id 
                        INNER JOIN sys.columns C 
		                        ON IC.object_id = C.object_id 
			                        AND IC.column_id = C.column_id
                        WHERE
                                I.type_desc <> N'HEAP'
                                AND UPPER(SCHEMA_NAME(T.[schema_id])) LIKE '$schemaMatchString'
                                AND UPPER(T.name) LIKE '$tableMatchString'
                                AND UPPER(I.name) LIKE '$indexMatchString'
                                AND UPPER(C.name) LIKE '$indexColumnNameMatchString'
                        ORDER BY 
                                TableName ASC, 
                                IndexName ASC;"

                $matchingIndexes = $db.Query($sql)

                #Returns:
                #DBName  IndexName  SchemaName  TableName  IsPrimaryKey  IsUnique  IsUniqueConstraint  IsMSShipped
                #------  ---------  ----------  ---------  ------------  --------  ------------------  -----------

                $stepName = "Loop through all tables in [$instance].[$($db.Name)]"
                #--------------------------------------------        
                Write-Message -Level Verbose -Message $stepName
                    
                #
                #Now get all the matching indexes from these tables
                #
                foreach($fullTableName in ($matchingIndexes | 
                                            Select-Object -ExpandProperty TableDotSchemaName -Unique))
                {

                    $stepName = "Get all indexes for table [$instance].[$($db.Name)].$fullTableName"
                    #--------------------------------------------        
                    Write-Message -Level Verbose -Message $stepName
                        
                    #Wish Get-DbaHelpIndex had an IndexName parameter but it doesn't (need to enhance)
                    #   so we get all indexes for the tables and then filter again!
                    #
                    #If Raw switch is enabled, results may be less user-readable but more suitable for processing by other code.
                    $allTableIndexes = Get-DbaHelpIndex `
                                    -SqlInstance $instance.FullName `
                                    -SqlCredential $SqlCredential `
                                    -Database $db.Name `
                                    -ObjectName $fullTableName `
                                    -IncludeStats: $IncludeStats `
                                    -IncludeDataTypes: $IncludeDataTypes `
                                    -Raw: $Raw `
                                    -IncludeFragmentation: $IncludeFragmentation `
                                    -EnableException: $EnableException
                                    

                    #Returns (approx. since display columns can vary when Select-Object * is not used). 
                    #  See Get-DbaHelpIndex help for more info.
                    #ComputerName  InstanceName  sqlInst  Database  Object  Index  IndexType  Statistics  KeyColumns  IncludeColumns
                    #------------  ------------  -------  --------  ------  -----  ---------  ----------  ----------  --------------


                    $stepName = "Filter based on IndexName match"
                    #--------------------------------------------        
                    Write-Message -Level Verbose -Message $stepName
                        
                    #Return value must be an array even if there is only one element 
                    #  hence the @ to cast the result to array and comma to preserve that type!
                    #
                    ,@($allTableIndexes |
                            Where-Object {$_.Object -eq $fullTableName} |
                            Where-Object {$_.Index -in ($matchingIndexes | 
                                                        Where-Object {$_.TableDotSchemaName -eq $fullTableName} |
                                                        Select-Object -ExpandProperty IndexName)
                                            }
                    )
               
                }
            }
        }
    }
}