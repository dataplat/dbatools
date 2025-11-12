function Get-DbaWaitResource {
    <#
    .SYNOPSIS
        Translates wait resource strings into human-readable database object information for troubleshooting blocking and deadlocks

    .DESCRIPTION
        Converts cryptic wait resource identifiers from sys.dm_exec_requests into readable database object details that DBAs can actually use for troubleshooting. When you're investigating blocking chains or deadlocks, you see wait_resource values like 'PAGE: 10:1:9180084' or 'KEY: 7:35457594073541168 (de21f92a1572)' in DMVs, but these don't tell you which actual table or index is involved.

        For PAGE wait resources, this function uses DBCC PAGE internally to identify the specific database, data file, schema, and object that owns the contested page. For KEY wait resources, it queries system catalog views to determine the database, schema, table, and index being waited on. With the -Row parameter, you can also retrieve the actual data from the locked row, which is invaluable for understanding what specific record is causing contention.

        This eliminates the manual detective work of decoding resource IDs and saves time when you need to quickly identify the root cause of blocking issues in production environments.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER WaitResource
        Specifies the cryptic wait resource identifier from sys.dm_exec_requests that you need to decode into readable database object information.
        Accepts PAGE format like 'PAGE: 10:1:9180084' or KEY format like 'KEY: 7:35457594073541168 (de21f92a1572)'.
        Use this when troubleshooting blocking chains or deadlocks to identify which specific table, index, or page is causing contention.

    .PARAMETER Row
        Returns the actual data from the locked row in addition to the object information for KEY wait resources.
        Provides the specific record values that are causing the lock contention, which helps identify patterns or problematic data.
        Only works with KEY wait resources and uses NOLOCK hint to retrieve the current row data safely.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Pages, DBCC
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWaitResource

    .EXAMPLE
        PS C:\> Get-DbaWaitResource -SqlInstance server1 -WaitResource 'PAGE: 10:1:9180084'

        Will return an object containing; database name, data file name, schema name and the object which owns the resource

    .EXAMPLE
        PS C:\> Get-DbaWaitResource -SqlInstance server2 -WaitResource 'KEY: 7:35457594073541168 (de21f92a1572)'

        Will return an object containing; database name, schema name and index name which is being waited on.

    .EXAMPLE
        PS C:\> Get-DbaWaitResource -SqlInstance server2 -WaitResource 'KEY: 7:35457594073541168 (de21f92a1572)' -row

        Will return an object containing; database name, schema name and index name which is being waited on, and in addition the contents of the locked row at the time the command is run.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstance]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [string]$WaitResource,
        [switch]$Row,
        [switch]$EnableException
    )

    process {
        if ($WaitResource -notmatch '^PAGE: [0-9]*:[0-9]*:[0-9]*$' -and $WaitResource -notmatch '^KEY: [0-9]*:[0-9]* \([a-f0-9]*\)$') {
            Stop-Function -Message "Row input - $WaitResource - Improperly formatted"
            return
        }

        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        }

        $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):*'
        $resourceType = $matches.Type
        $dbId = $matches.DbId
        $dbName = ($server.Databases | Where-Object ID -eq $dbId).Name
        if ($null -eq $dbName) {
            stop-function -Message "Database with id $dbId does not exist on $server"
            return
        }
        if ($resourceType -eq 'PAGE') {
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<FileID>[0-9]*):(?<PageID>[0-9]*)$'
            $dataFileSql = "SELECT name, physical_name FROM sys.master_files WHERE database_id=$dbId AND file_ID=$($matches.FileID);"
            $dataFile = $server.query($dataFileSql)
            if ($null -eq $dataFile) {
                Write-Message -Level Warning -Message "Datafile with id $($matches.FileID) for $dbName not found"
                return
            }
            $objectIdSql = "DBCC TRACEON (3604); DBCC PAGE ($dbId,$($matches.fileID),$($matches.PageID),2) WITH TABLERESULTS;"
            try {
                $objectId = ($server.databases[$dbName].Query($objectIdSql) | Where-Object Field -eq 'Metadata: ObjectId').Value
            } catch {
                Stop-Function -Message "You've requested a page beyond the end of the database, exiting"
                return
            }
            if ($null -eq $objectId) {
                Write-Message -Level Warning -Message "Object not found, could have been delete, or a transcription error when copying the Wait_resource to PowerShell"
                return
            }
            $objectSql = "SELECT SCHEMA_NAME(schema_id) AS SchemaName, name, type_desc FROM sys.all_objects WHERE object_id=$objectId;"
            $object = $server.databases[$dbName].query($objectSql)
            if ($null -eq $object) {
                Write-Message -Warning "Object could not be found. Could have been removed, or could be a transcription error copying the Wait_resource to sowerShell"
            }
            [PSCustomObject]@{
                DatabaseID   = $dbId
                DatabaseName = $dbName
                DataFileName = $dataFile.name
                DataFilePath = $dataFile.physical_name
                ObjectID     = $objectId
                ObjectName   = $object.Name
                ObjectSchema = $object.SchemaName
                ObjectType   = $object.type_desc
            }
        }
        if ($resourceType -eq 'KEY') {
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<frodo>[0-9]*) (?<physloc>\(.*\))$'
            $indexSql = "SELECT
                            sp.object_id AS ObjectID,
                            OBJECT_SCHEMA_NAME(sp.object_id) AS SchemaName,
                            sao.name AS ObjectName,
                            si.name AS IndexName
                        FROM
                            sys.partitions sp INNER JOIN sys.indexes si ON sp.index_id=si.index_id AND sp.object_id=si.object_id
                                INNER JOIN sys.all_objects sao ON sp.object_id=sao.object_id
                        WHERE
                            hobt_id = $($matches.frodo);
                "
            $index = $server.databases[$dbName].Query($indexSql)
            if ($null -eq $index) {
                Write-Message -Level Warning -Message "Heap or B-Tree with ID $($matches.frodo) can not be found in $dbName on $server"
                return
            }
            $output = [PSCustomObject]@{
                DatabaseID   = $dbId
                DatabaseName = $dbName
                SchemaName   = $index.SchemaName
                IndexName    = $index.IndexName
                ObjectID     = $index.ObjectID
                Objectname   = $index.ObjectName
                HobtID       = $matches.frodo
            }
            if ($row -eq $True) {
                $dataSql = "SELECT * FROM $($index.SchemaName).$($index.ObjectName) WITH (NOLOCK) WHERE %%lockres%% ='$($matches.physloc)'"
                $data = $server.databases[$dbName].query($dataSql)
                if ($null -eq $data) {
                    Write-Message -Level warning -Message "Could not retrieve the data. It may have been deleted or moved since the wait resource value was generated"
                } else {
                    $output | Add-Member -Type NoteProperty -Name ObjectData -Value $data
                    $output | Select-Object * -ExpandProperty ObjectData
                }
            } else {
                $output
            }
        }
    }
}