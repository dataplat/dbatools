function Get-DbaWaitResource {
    <#
    .SYNOPSIS
        Returns the resource being waited upon

    .DESCRIPTION
        Given a wait resource in the form of:
            'PAGE: 10:1:9180084 '
        returns the database, data file and the system oject which is being waited up
        Given a wait resource in the form of:
            'KEY: 7:35457594073541168 (de21f92a1572)'
        returns the database, object and index that is being waited on, With the -row switch the row data will also be returned
    .PARAMETER SqlInstance
        The SQL Server instance to restore to.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.

    .PARAMETER WaitResource
        The waitresource value as supplied in sys.dm_exec_requests

    .PARAMETER Row
        If this switch provided also returns the value of the row being waited on with KEY wait resources

    .PARAMETER EnableException
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.

    .EXAMPLE
        Get-DbaWaitResource -SqlInstance server1 -WaitResource 'PAGE: 10:1:9180084'

        Will return an object containing; database name, data file name, schema name and the object which owns the resouce

    .EXAMPLE
        Get-DbaWaitResource -Sql Instance server2 -WaitResource 'KEY: 7:35457594073541168 (de21f92a1572)'

        Will return an object containing; database name, schema name and index name which is being waited on

    .EXAMPLE
        Get-DbaWaitResource -Sql Instance server2 -WaitResource 'KEY: 7:35457594073541168 (de21f92a1572)' -row

        Will return an object containing; database name, schema name and index name which is being waited on, and in addition the contents of the locked row at the time the command is run

    .NOTES
        Tags: Pages, DBCC
        Author: Stuart Moore (@napalmgram), stuart-moore.com

        dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
        Copyright (C) 2016 Chrissy LeMaire
        License: MIT https://opensource.org/licenses/MIT
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance]$SqlInstance,
        [PsCredential]$SqlCredential,
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$WaitResource,
        [switch]$Row,
        [switch]$EnableException
    )

    process {
        if ($WaitResource -notmatch '^PAGE: [0-9]*:[0-9]*:[0-9]*$' -and $WaitResource -notmatch '^KEY: [0-9]*:[0-9]* \([a-f0-9]*\)$'){
           Stop-Function -Message "Row input - $WaitResource - Improperly formatted"
           return
        }

        try {
            $server = Connect-SqlInstance -SqlInstance $sqlinstance -SqlCredential $SqlCredential
        }
        catch {
            Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
        }

        $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):*'
        $ResourceType = $matches.Type
        $DbId = $matches.DbId
        $DbName = ($server.Databases | Where-Object ID -eq $dbid).Name
        if ($null -eq $DbName){
            stop-function -Message "Database with id $dbid does not exist on $server"
            return
        }
        if ($ResourceType -eq 'PAGE'){
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<FileID>[0-9]*):(?<PageID>[0-9]*)$'
            $DataFileSql = "select name, physical_name from sys.master_files where database_id=$DbID and file_ID=$($matches.FileID);"
            $DataFile = $server.query($DataFileSql)
            if ($null -eq $DataFile){
                Write-Message -Level Warning -Message "Datafile with id $($matches.FileID) for $dbname not found"
                return
            }
            $ObjectIdSQL = "dbcc traceon (3604); dbcc page ($dbid,$($matches.fileID),$($matches.PageID),2) with tableresults;"
            try {
                $ObjectID = ($server.databases[$dbname].Query($ObjectIdSQL) | Where-Object Field -eq 'Metadata: ObjectId').Value
            }
            catch {
                Stop-Function -Message "You've requested a page beyond the end of the database, exiting"
                return
            }
            if ($null -eq $ObjectID){
            Write-Message -Level Warning -Message "Object not found, could have been delete, or a transcription error when copying the Wait_resource to PowerShell"
            return
            }
            $ObjectSql = "select SCHEMA_NAME(schema_id) as SchemaName, name, type_desc from sys.all_objects where object_id=$objectID;"
            $Object = $server.databases[$dbname].query($ObjectSql)
            if ($null -eq $Object){
                Write-Message -Warning "Object could not be found. Could have been removed, or could be a transcription error copying the Wait_resource to sowerShell"
            }
            [PsCustomObject]@{
                DatabaseID = $DbId
                DatabaseName = $DbName
                DataFileName = $Datafile.name
                DataFilePath = $DataFile.physical_name
                ObjectID = $ObjectID
                ObjectName = $Object.Name
                ObjectSchema = $Object.SchemaName
                ObjectType = $Object.type_desc
            }
        }
        if ($ResourceType -eq 'KEY'){
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<frodo>[0-9]*) (?<physloc>\(.*\))$'
            $IndexSql = "select
                            sp.object_id as ObjectID,
                            OBJECT_SCHEMA_NAME(sp.object_id) as SchemaName,
                            sao.name as ObjectName,
                            si.name as IndexName
                        from
                            sys.partitions sp inner join sys.indexes si on sp.index_id=si.index_id and sp.object_id=si.object_id
                                inner join sys.all_objects sao on sp.object_id=sao.object_id
                        where
                            hobt_id = $($matches.frodo);
                "
            $Index = $server.databases[$dbname].Query($IndexSql)
            if ($null -eq $Index){
                Write-Message -Level Warning -Message "Heap or B-Tree with ID $($matches.frodo) can not be found in $dbname on $server"
                return
            }
            $output = [PsCustomObject]@{
                DatabaseID = $DbId
                DatabaseName = $DbName
                SchemaName = $Index.SchemaName
                IndexName = $Index.IndexName
                ObjectID = $index.ObjectID
                Objectname = $index.ObjectName
                HobtID = $matches.frodo
            }
            if ($row -eq $True){
                $DataSql = "select * from $($Index.SchemaName).$($Index.ObjectName) with (NOLOCK) where %%lockres%% ='$($matches.physloc)'"
                $Data = $server.databases[$dbname].query($DataSql)
                if ($null -eq $data){
                    Write-Message -Level warning -Message "Could not retrieve the data. It may have been deleted or moved since the wait resource value was generated"
                }
                else{
                    $output | Add-Member -Type NoteProperty -Name ObjectData -Value $Data
                    $output | Select-Object * -ExpandProperty ObjectData
                }
            }
            else {
                $output
            }
        }
    }
}