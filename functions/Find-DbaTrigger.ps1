function Find-DbaTrigger {
    <#
.SYNOPSIS
Returns all triggers that contain a specific case-insensitive string or regex pattern.

.DESCRIPTION
This function search on Instance, Database and Object level.
If you specify one or more databases, search on Server level will not be preformed.

.PARAMETER SqlInstance
SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input

.PARAMETER SqlCredential
Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

.PARAMETER Database
The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

.PARAMETER ExcludeDatabase
The database(s) to exclude - this list is auto-populated from the server

.PARAMETER Pattern
String pattern that you want to search for in the trigger textbody

.PARAMETER TriggerLevel
Allows specify the trigger level that you want to search. By default is All (Server, Database, Object).

.PARAMETER IncludeSystemObjects
By default, system triggers are ignored but you can include them within the search using this parameter.

Warning - this will likely make it super slow if you run it on all databases.

.PARAMETER IncludeSystemDatabases
By default system databases are ignored but you can include them within the search using this parameter

.PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

.NOTES
Author: Cláudio Silva, @ClaudioESSilva

Website: https://dbatools.io
Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
License: MIT https://opensource.org/licenses/MIT

.LINK
https://dbatools.io/Find-DbaTrigger

.EXAMPLE
Find-DbaTrigger -SqlInstance DEV01 -Pattern whatever

Searches all user databases triggers for "whatever" in the textbody

.EXAMPLE
Find-DbaTrigger -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

Searches all databases for all triggers that contain a valid email pattern in the textbody

.EXAMPLE
Find-DbaTrigger -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

Searches in "mydb" database triggers for "some string" in the textbody

.EXAMPLE
Find-DbaTrigger -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

Searches in "mydb" database triggers for "runtime" in the textbody

#>
    [CmdletBinding()]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory = $true)]
        [string]$Pattern,
        [ValidateSet('All', 'Server', 'Database', 'Object')]
        [string]$TriggerLevel = 'All',
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        $sqlDatabaseTriggers = "SELECT tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 0"

        $sqlTableTriggers = "SELECT OBJECT_SCHEMA_NAME(tr.parent_id) TableSchema, OBJECT_NAME(tr.parent_id) AS TableName, tr.name, m.definition as TextBody FROM sys.sql_modules m, sys.triggers tr WHERE m.object_id = tr.object_id AND tr.parent_class = 1"
        if (!$IncludeSystemObjects) { $sqlTableTriggers = "$sqlTableTriggers AND tr.is_ms_shipped = 0" }

        $everyserverstcount = 0
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $Instance"
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            }
            catch {
                Write-Message -Level Warning -Message "Failed to connect to: $Instance"
                continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            #search at instance level. Only if no database was specified
            if ((-Not $Database) -and ($TriggerLevel -in @('All', 'Server'))) {
                foreach ($trigger in $server.Triggers) {
                    $everyserverstcount++; $triggercount++
                    Write-Message -Level Debug -Message "Looking in Trigger: $trigger TextBody for $pattern"
                    if ($trigger.TextBody -match $Pattern) {

                        $triggerText = $trigger.TextBody.split("`n`r")
                        $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                        [PSCustomObject]@{
                            ComputerName     = $server.NetName
                            SqlInstance      = $server.ServiceName
                            TriggerLevel     = "Server"
                            Database         = $null
                            Object           = $null
                            Name             = $trigger.Name
                            IsSystemObject   = $trigger.IsSystemObject
                            CreateDate       = $trigger.CreateDate
                            LastModified     = $trigger.DateLastModified
                            TriggerTextFound = $trTextFound -join "`n"
                            Trigger          = $trigger
                            TriggerFullText  = $trigger.TextBody
                        } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                    }
                }
                Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $server"
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            }
            else {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" -and $_.IsSystemObject -eq $false }
            }

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            $totalcount = 0
            $dbcount = $dbs.count

            if ($TriggerLevel -in @('All', 'Database', 'Object')) {
                foreach ($db in $dbs) {

                    Write-Message -Level Verbose -Message "Searching on database $db"

                    # If system objects aren't needed, find trigger text using SQL
                    # This prevents SMO from having to enumerate

                    if (!$IncludeSystemObjects) {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            Write-Message -Level Debug -Message $sqlDatabaseTriggers
                            $rows = $db.ExecuteWithResults($sqlDatabaseTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($row.TextBody -match $Pattern) {
                                    $tr = $db.Triggers | Where-Object name -eq $row.name

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.NetName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            Write-Message -Level Debug -Message $sqlTableTriggers
                            $rows = $db.ExecuteWithResults($sqlTableTriggers).Tables.Rows
                            $triggercount = 0

                            foreach ($row in $rows) {
                                $totalcount++; $triggercount++; $everyserverstcount++

                                $trigger = $row.name
                                $triggerParentSchema = $row.TableSchema
                                $triggerParent = $row.TableName

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $triggerParentSchema.$triggerParent at database $db"
                                if ($row.TextBody -match $Pattern) {

                                    $tr = ($db.Tables | Where-Object {$_.Name -eq $triggerParent -and $_.Schema -eq $triggerParentSchema}).Triggers | Where-Object name -eq $row.name

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.NetName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    }
                    else {
                        if ($TriggerLevel -in @('All', 'Database')) {
                            #Get Database Level triggers (DDL)
                            $triggers = $db.Triggers

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern on database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.NetName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Database"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }

                        if ($TriggerLevel -in @('All', 'Object')) {
                            #Get Object Level triggers (DML)
                            $triggers = $db.Tables | ForEach-Object {$_.Triggers}

                            $triggercount = 0

                            foreach ($tr in $triggers) {
                                $totalcount++; $triggercount++; $everyserverstcount++
                                $trigger = $tr.Name

                                Write-Message -Level Verbose -Message "Looking in trigger $trigger for textBody with pattern $pattern in object $($tr.Parent) at database $db"
                                if ($tr.TextBody -match $Pattern) {

                                    $triggerText = $tr.TextBody.split("`n`r")
                                    $trTextFound = $triggerText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                                    [PSCustomObject]@{
                                        ComputerName     = $server.NetName
                                        SqlInstance      = $server.ServiceName
                                        TriggerLevel     = "Object"
                                        Database         = $db.name
                                        Object           = $tr.Parent
                                        Name             = $tr.Name
                                        IsSystemObject   = $tr.IsSystemObject
                                        CreateDate       = $tr.CreateDate
                                        LastModified     = $tr.DateLastModified
                                        TriggerTextFound = $trTextFound -join "`n"
                                        Trigger          = $tr
                                        TriggerFullText  = $tr.TextBody
                                    } | Select-DefaultView -ExcludeProperty Trigger, TriggerFullText
                                }
                            }
                        }
                    }
                    Write-Message -Level Verbose -Message "Evaluated $triggercount triggers in $db"
                }
            }
            Write-Message -Level Verbose -Message "Evaluated $totalcount total triggers in $dbcount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Evaluated $everyserverstcount total triggers"
    }
}
