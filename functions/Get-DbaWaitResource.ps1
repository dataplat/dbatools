function Get-DbaWaitResource {
    <#
    .SYNOPSIS
        Returns the resource being waited 

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
        Tags: 
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
        if ($dbname -eq ''){
        
        }
        if ($ResourceType -eq 'PAGE'){
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<FileID>[0-9]*):(?<PageID>[0-9]*)$'
            $DataFileSql = "select name, physical_name from sys.master_files where database_id=$DbID and file_ID=$($matches.FileID);"
            $DataFile = $server.query($DataFileSql)
            $ObjectIdSQL = "dbcc traceon (3604); dbcc page ($dbid,$($matches.fileID),$($matches.PageID),2) with tableresults;"
            $ObjectID = ($server.databases[$dbname].Query($ObjectIdSQL) | Where-Object Field -eq 'Metadata: ObjectId').Value
            $ObjectSql = "select SCHEMA_NAME(schema_id) as SchemaName, name, type_desc from sys.all_objects where object_id=$objectID;"
            $Object = $server.databases[$dbname].query($ObjectSql)
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
            $null = $WaitResource -match '^(?<Type>[A-Z]*): (?<dbid>[0-9]*):(?<frodo>[0-9]*) \((?<physloc>.*)\)$'
            $IndexSql = "select 
                            sp.object_id as ObjectID,
                            OBJECT_SCHEMA_NAME(sp.object_id) as SchemaName, 
                            sao.name as ObjectName, 
                            si.name as IndexName
                        from 
                            sys.partitions sp inner join sys.indexes si on sp.index_id=si.index_id
                                inner join sys.all_objects sao on sp.object_id=sao.object_id
                        where 
                            hobt_id = $($matches.frodo);
                "
            $Index = $server.databases[$dbname].Query($IndexSql)
            $output = [PsCustomObject]@{
                DatabaseID = $DbId
                DatabaseName = $DbName
                SchemaName = $Index.IndexName
                ObjectID = $index.ObjectID
                Objectname = $index.ObjectName
                HobtID = $matches.frodo
            }
            if ($row -eq $True){
                $DataSql = "select * from $($Index.SchemaName).$($Index.ObjectName) with (NOLOCK) where %%lockres%% ='($($matches.physloc))'"
                $Data = $server.databases[$dbname].query($DataSql)
                $output | Add-Member -Type NoteProperty -Name ObjectData -Value $Data
            }
            $output
        }
    }
}