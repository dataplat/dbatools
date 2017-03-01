function Start-DbaDiagnosticQuery
{
<#
.SYNOPSIS 
Start-DbaDiagnosticQuery runs the scripts provided by Glenn Berry's DMV scripts on specified servers.

.DESCRIPTION
This is the main function of the Sql Server Diagnostic Queries related functions in dbatools. 
The diagnostic queries are developed and maintained by Glenn Berry and they can be found here along with a lot of documentation:
http://www.sqlskills.com/blogs/glenn/category/dmv-queries/

The most recent version of the diagnostic queries are included in the dbatools module. 
But it is possible to download a newer set or a specific version to an alternative location and parse and run those scripts.
It will run all or a selection of those scripts on one or multiple servers and export the result to either clixml, csv or excel.

The excel output relies on the ImportExcel module by Doug Finke (https://github.com/dfinke/ImportExcel), which is not part of dbatools
The default output is clixml. 
The default directory for the output is the "my documents" directory. This is also the default directory for checking for the presense of the .sql files.
And it is the directory where the .sql files will be downloaded to if no alternative directory is specified.
	
.EXAMPLE   
Start-DbaDiagnosticQuery 

Runs all scripts for the default instance on the local computer and saves the output in the "My Documents" directory in clixml format

.EXAMPLE   
Start-DbaDiagnosticQuery -SqlServer mysqlserver -OutputType excel -UseSelectionHelper

Provides a gridview with all the queries to choose from and will run the selection made by the user on the Sql Server instance specified. 
It will output the results into Excel files. (This feature requires the ImportExcel module (https://github.com/dfinke/ImportExcel)

#>

[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
Param(
	[parameter(ValueFromPipeline = $true)]
 	[string]$SqlServer = $env:COMPUTERNAME,
    [ValidateSet(“excel”,”csv”,”clixml”)] 
    [string]$OutputType = "clixml",
    [ValidateScript({Test-Path $_})]
    [System.IO.FileInfo]$OutputLocation = [Environment]::GetFolderPath("mydocuments"),
    [ValidateScript({Test-Path $_})]
    [System.IO.FileInfo]$ScriptLocation = $PSModulePath + "internal\content", 
    [string[]]$QueryName,
    [switch]$UseSelectionHelper,
    [switch]$InstanceOnly,
    [switch]$DBSpecificOnly,
    [switch]$NoProgressBar
	)

    BEGIN
    {
        if ($OutputType -eq "excel")
        {
            try
            {
                Import-Module ImportExcel -ErrorAction Stop
            }
            catch
            {
                Write-Output "Failed to load module, exporting to Excel feature is not available"
                Write-Output "Install the module from: https://github.com/dfinke/ImportExcel"
                Write-Output "Valid alternative export formats are csv and clixml"
                break
            }
        }

        $Sqlservers = @()
        Write-Verbose -Message "Interpreting DMV Script Collections"

        $scriptversions = @()

        $scriptfiles = Get-ChildItem "$ScriptLocation\SQLServerDiagnosticQueries_*_*.sql"

        if (!$scriptfiles)
        {
            Write-Verbose "No files, download?"
            Get-DbaDiagnosticQueryScript -ScriptLocation $ScriptLocation
            $scriptfiles = Get-ChildItem "$ScriptLocation\SQLServerDiagnosticQueries_*_*.sql"
            if (!$scriptfiles)
            {
                write-output "Unable to download scripts, do you have an internet connection?"
                break
            }
        }

        [int[]]$filesort = $null

        foreach($file in $scriptfiles)
        {
            $filesort += $file.BaseName.Split("_")[2]
        }

        $currentdate = $filesort | Sort-Object -Descending | Select-Object -First 1

        foreach($file in $scriptfiles)
        {
            if ($file.BaseName.Split("_")[2] -eq $currentdate)
            {
                $script = Invoke-DbaDiagnosticQueryScriptParser -filename $file.fullname
                $properties = @{Version = $file.basename.split("_")[1]; Script = $script}
                $newscript = New-Object -TypeName PSObject -Property $properties
                $scriptversions += $newscript
            }
        }
    }


    PROCESS
    {
        $Sqlservers += New-Object -TypeName PSObject -Property @{SqlServer = $SqlServer}
    }

    END
    {
        Write-Output "Running diagnostic queries on $($SqlServers.count) server(s), exporting to $OutputType at $OutputLocation" 
        $servercounter = 0
        foreach ($SqlServer in $SqlServers | Select-Object -ExpandProperty SqlServer)
        {
            $servercounter += 1
            $clixml = @()

            $smoSqlServer = Connect-DbaSqlServer -SqlServer $SqlServer

            $out = "Collecting diagnostic query Data from Server: {0}" -f $SqlServer
            Write-Verbose -Message $out

            if (!$NoProgressBar){Write-Progress -Id 0 -Activity "Running Scripts on SQL Server" -Status ("Instance {0} of {1}" -f $servercounter, $sqlservers.count) -CurrentOperation $SqlServer -PercentComplete (($servercounter / $SqlServers.count) * 100)}

            if ($smoSqlServer.VersionMinor -eq 50)
            {
                $version = "2008R2"
            }
            else
            {
                switch ($smoSqlServer.VersionMajor)
                {
                     9 {$version = "2005"}
                    10 {$version = "2008"}
                    11 {$version = "2012"}
                    12 {$version = "2014"}
                    13 {$version = "2016"}
                    14 {$version = "vNext"}
                }
            }

            if (!$InstanceOnly)
            {
                $databases = Invoke-Sqlcmd -ServerInstance $SqlServer -Database master -Query "Select Name from sys.databases where name not in ('master', 'model', 'msdb', 'tempdb')" 
            }

            $script = $scriptversions | Where-Object -Property Version -EQ $version | Select-Object -ExpandProperty Script

            if ($null -eq $first) {$first = $true}
            if ($UseSelectionHelper -and $first)
            {
                $QueryName = Invoke-DbaDiagnosticQueriesSelectionHelper $script
                $first = $false
            }

            if (!$instanceonly -and !$DBSpecificOnly -and !$QueryName)
            {
                $scriptcount = $script.count
            }
            elseif ($InstanceOnly)
            {
                $scriptcount = ($script | Where-Object DBSpecific -eq $false).count
            }
            elseif ($DBSpecificOnly)
            {
                $scriptcount = ($script | Where-Object DBSpecific).count
            }
            elseif ($QueryName.Count -ne 0)
            {
                $scriptcount = $QueryName.Count
            }

            $Counter = 0
            foreach ($scriptpart in $script)
            {
                if (($QueryName.Count -ne 0) -and ($QueryName -notcontains $scriptpart.QueryName)){continue}
                if (!$scriptpart.DBSpecific -and !$DBSpecificOnly)
                {
                    $Counter += 1
                    if ($PSCmdlet.ShouldProcess($SqlServer, $scriptpart.QueryName))
                    {
                        if (!$NoProgressBar){Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic queries Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100)}
                        try
                        {
                            $result = Invoke-Sqlcmd -ServerInstance $SqlServer -Database master -Query $($scriptpart.Text) -ErrorAction Stop
                            if (!$result)
                            {
                                $result = New-Object -type PSObject -Property @{QueryNr=$scriptpart.QueryNr; Name=$scriptpart.Name; Message="Empty Result for this Query"}
                                Write-Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.Name, $scriptpart.Description)
                            }
                        }
                        catch
                        {
                            Write-Verbose -Message ('Some error has occured on Server: {0} - Script: {1}, result will not be saved' -f $SqlServer, $Scriptpart.name)
                        }
                        if ($result)
                        {
                            switch ($OutputType)
                            {
                                "Excel"  {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Excel -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$")).xlsx -WorkSheetname $($scriptpart.QueryName) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow}
                                "CSV"    {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Csv -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($scriptpart.QueryNr)_$($scriptpart.QueryName.Replace(" ", "_")).csv -NoTypeInformation}
                                "CliXml" 
                                {
                                    $clixmlresult = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
                                    $clixml += New-Object -TypeName PSObject -Property @{QueryNr=$scriptpart.QueryNr; Name=$scriptpart.QueryName; Description=$scriptpart.Description; DBSpecific=$scriptpart.DBSpecific; DatabaseName=$null; Result=$clixmlresult}
                                }
                            }
                            
                        }
                    }
                }
                elseif ($scriptpart.DBSpecific -and !$InstanceOnly)
                {
                    $Counter += 1
                    foreach ($database in $databases)
                    {
                        if ($PSCmdlet.ShouldProcess(('{0} ({1})' -f $SqlServer, $database.name), $scriptpart.QueryName))
                        {
                            if (!$NoProgressBar){Write-Progress -Id 0 -Activity "Running diagnostic queries on SQL Server" -Status ("Instance {0} of {1}" -f $servercounter, $sqlservers.count) -CurrentOperation $SqlServer -PercentComplete (($servercounter / $SqlServers.count) * 100)}
                            if (!$NoProgressBar){Write-Progress -Id 1 -ParentId 0 -Activity "Collecting diagnostic query Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100)}
                            try
                            {
                                $result = Invoke-Sqlcmd -ServerInstance $SqlServer -Database $($database.Name) -Query $($scriptpart.Text) -ErrorAction Stop
                                if (!$result)
                                {
                                    $result = New-Object -type PSObject -Property @{QueryNr=$scriptpart.QueryNr; Name=$scriptpart.Name; Message="Empty Result for this Query"}
                                    Write-Verbose -Message ("Empty result for Query {0} - {1} - {2}" -f $scriptpart.QueryNr, $scriptpart.Name, $scriptpart.Description)
                                }
                            }
                            catch
                            {
                                Write-Verbose -Message ('Some error has occured on Server: {0} - Script: {1} - Database: {2}, result will not be saved' -f $SqlServer, $scriptpart.name, $database.Name)
                            }
                            if ($result)
                            {
                                switch ($OutputType)
                                {
                                    "Excel"  {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Excel -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($database.name).xlsx -WorkSheetname $($scriptpart.QueryName) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow}
                                    "CSV"    {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Csv -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$"))_$($database.name)_$($scriptpart.QueryNr)_$($scriptpart.QueryName.Replace(" ", "_")).csv -NoTypeInformation}
                                    "CliXml" 
                                    {
                                        $clixmlresult = $result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors
                                        $clixml += New-Object -TypeName PSObject -Property @{QueryNr=$scriptpart.QueryNr; Name=$scriptpart.QueryName; Description=$scriptpart.Description; DBSpecific=$scriptpart.DBSpecific; DatabaseName=$database.name; Result=$clixmlresult}
                                    }
                                }
                            }
                        } 
                    }                
                }
            }
        if ($OutputType -eq "CliXml"){$clixml | Export-Clixml -Path $OutputLocation\SqlServerDiagnosticQueries_$($sqlserver.Replace("\", "$")).clixml}
        }
    }

}

