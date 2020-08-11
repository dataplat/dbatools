function Get-DbaFileStreamFolder {
    <#

    .SYNOPSIS
        Returns basic information about Filestream folders from a Sql Instance

    .DESCRIPTION
        Given a SQL Instance, and an optional list of databases returns the FileStream containing folders on that Instance. Without the Database parameter, all dbs with FileStream are returned

    .PARAMETER SqlInstance
        The Sql Server instance to be queries

    .PARAMETER SqlCredential
        A Sql Credential to connect to $SqlInstance

    .PARAMETER Database
        Database to be tested, multiple databases may be specified as a comma seperated list.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .EXAMPLE
        Get-DbaFileStreamFolder -SqlInstance server1\instance2

        Returns all FileStream folders from server1\instance2

    .EXAMPLE
        Get-DbaFileStreamFolder -SqlInstance server1\instance2 -Database Archive

        Returns any FileStream folders from the Archive database on server1\instance2

    .NOTES
    Author:Stuart Moore (@napalmgram stuart-moore.com )


    Website: https://dbatools.io
    Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT
    #>
    param (
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [switch]$EnableException
    )

    begin {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failed to process Instance $SqlInstance." -InnerErrorRecord $_ -Target $SqlInstance -Continue
        }
    }

    process {
        $sql = "select d.name as 'dbname', mf.Physical_Name from sys.master_files mf inner join sys.databases d on mf.database_id = d.database_id
        where mf.type=2"
        $databases = @()
        if ($null -ne $Database) {
            ForEach ($db in $Database) {
                $databases += "'$db'"
            }
            $sql = $sql + " and d.name in ( $($databases -join ',') )"
        }

        $results = $server.ConnectionContext.ExecuteWithResults($sql).Tables.Rows | Select-Object * -ExcludeProperty  RowError, Rowstate, table, itemarray, haserrors
        foreach ($result in $results) {
            [PsCustomObject]@{
                ServerInstance   = $SqlInstance
                Database         = $result.dbname
                FileStreamFolder = $result.Physical_Name
            }
        }


    }

    END { }
}