function Find-DbaView {
    <#
    .SYNOPSIS
        Returns all views that contain a specific case-insensitive string or regex pattern.

    .DESCRIPTION
        This function can either run against specific databases or all databases searching all user or user and system views.

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

    .PARAMETER Pattern
        String pattern that you want to search for in the view text body

    .PARAMETER IncludeSystemObjects
        By default, system views are ignored but you can include them within the search using this parameter.

        Warning - this will likely make it super slow if you run it on all databases.

    .PARAMETER IncludeSystemDatabases
        By default system databases are ignored but you can include them within the search using this parameter

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: View
        Author: Claudio Silva  (@ClaudioESSilva)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Find-DbaView

    .EXAMPLE
        PS C:\> Find-DbaView -SqlInstance DEV01 -Pattern whatever

        Searches all user databases views for "whatever" in the text body

    .EXAMPLE
        PS C:\> Find-DbaView -SqlInstance sql2016 -Pattern '\w+@\w+\.\w+'

        Searches all databases for all views that contain a valid email pattern in the text body

    .EXAMPLE
        PS C:\> Find-DbaView -SqlInstance DEV01 -Database MyDB -Pattern 'some string' -Verbose

        Searches in "mydb" database views for "some string" in the text body

    .EXAMPLE
        PS C:\> Find-DbaView -SqlInstance sql2016 -Database MyDB -Pattern RUNTIME -IncludeSystemObjects

        Searches in "mydb" database views for "runtime" in the text body

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(Mandatory)]
        [string]$Pattern,
        [switch]$IncludeSystemObjects,
        [switch]$IncludeSystemDatabases,
        [switch]$EnableException
    )

    begin {
        $sql = "SELECT OBJECT_SCHEMA_NAME(vw.object_id) as ViewSchema, vw.name, m.definition as TextBody FROM sys.sql_modules m, sys.views vw WHERE m.object_id = vw.object_id"
        if (!$IncludeSystemObjects) { $sql = "$sql AND vw.is_ms_shipped = 0" }
        $everyservervwcount = 0
    }
    process {
        foreach ($Instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $Instance -SqlCredential $SqlCredential
            } catch {
                Write-Message -Level Warning -Message "Failed to connect to: $Instance"
                continue
            }

            if ($server.versionMajor -lt 9) {
                Write-Message -Level Warning -Message "This command only supports SQL Server 2005 and above."
                Continue
            }

            if ($IncludeSystemDatabases) {
                $dbs = $server.Databases | Where-Object { $_.Status -eq "normal" }
            } else {
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
            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Searching on database $db"

                # If system objects aren't needed, find view text using SQL
                # This prevents SMO from having to enumerate

                if (!$IncludeSystemObjects) {
                    Write-Message -Level Debug -Message $sql
                    $rows = $db.ExecuteWithResults($sql).Tables.Rows
                    $vwcount = 0

                    foreach ($row in $rows) {
                        $totalcount++; $vwcount++; $everyservervwcount++

                        $viewSchema = $row.ViewSchema
                        $view = $row.name

                        Write-Message -Level Verbose -Message "Looking in View: $viewSchema.$view TextBody for $pattern"
                        if ($row.TextBody -match $Pattern) {
                            $vw = $db.Views | Where-Object { $_.Schema -eq $viewSchema -and $_.Name -eq $view }

                            $viewText = $vw.TextBody.split("`n`r")
                            $vwTextFound = $viewText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                            [PSCustomObject]@{
                                ComputerName   = $server.ComputerName
                                SqlInstance    = $server.ServiceName
                                Database       = $db.Name
                                Schema         = $vw.Schema
                                Name           = $vw.Name
                                Owner          = $vw.Owner
                                IsSystemObject = $vw.IsSystemObject
                                CreateDate     = $vw.CreateDate
                                LastModified   = $vw.DateLastModified
                                ViewTextFound  = $vwTextFound -join "`n"
                                View           = $vw
                                ViewFullText   = $vw.TextBody
                            } | Select-DefaultView -ExcludeProperty View, ViewFullText
                        }
                    }
                } else {
                    $Views = $db.Views

                    foreach ($vw in $Views) {
                        $totalcount++; $vwcount++; $everyservervwcount++

                        $viewSchema = $row.ViewSchema
                        $view = $vw.Name

                        Write-Message -Level Verbose -Message "Looking in View: $viewSchema.$view TextBody for $pattern"
                        if ($vw.TextBody -match $Pattern) {

                            $viewText = $vw.TextBody.split("`n`r")
                            $vwTextFound = $viewText | Select-String -Pattern $Pattern | ForEach-Object { "(LineNumber: $($_.LineNumber)) $($_.ToString().Trim())" }

                            [PSCustomObject]@{
                                ComputerName   = $server.ComputerName
                                SqlInstance    = $server.ServiceName
                                Database       = $db.Name
                                Schema         = $vw.Schema
                                Name           = $vw.Name
                                Owner          = $vw.Owner
                                IsSystemObject = $vw.IsSystemObject
                                CreateDate     = $vw.CreateDate
                                LastModified   = $vw.DateLastModified
                                ViewTextFound  = $vwTextFound -join "`n"
                                View           = $vw
                                ViewFullText   = $vw.TextBody
                            } | Select-DefaultView -ExcludeProperty View, ViewFullText
                        }
                    }
                }
                Write-Message -Level Verbose -Message "Evaluated $vwcount views in $db"
            }
            Write-Message -Level Verbose -Message "Evaluated $totalcount total views in $dbcount databases"
        }
    }
    end {
        Write-Message -Level Verbose -Message "Evaluated $everyservervwcount total views"
    }
}