function Get-DbaGlennBerryDMV
{
<#
.SYNOPSIS 
Get-DbaGlennBerryDMV runs the scripts provided by Glenn Berry's DMV scripts on specified servers.

.DESCRIPTION
This is the main function of the GlennBerryDMV related functions in dbatools. 
It will download the most recent version of all .sql files from Glenn Berry if they are not available.
It will run all or a selection of those scripts on one or multiple servers and export the result to either clixml, csv or excel.

The excel output relies on the ImportExcel module by Doug Finke (https://github.com/dfinke/ImportExcel), which is not part of dbatools
The default output is clixml. 
The default directory for the output is the "my documents" directory. This is also the default directory for checking for the presense of the .sql files.
And it is the directory where the .sql files will be downloaded to if no alternative directory is specified.
	
.EXAMPLE   
Get-DbaGlennBerryDMV 

Runs all scripts for the default instance on the local computer and saves the output in the "My Documents" directory in clixml format

.EXAMPLE   


Copies a single custom error, the custom error with ID number 6000 from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.

.EXAMPLE   
Copy-SqlCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>

[CmdletBinding(DefaultParameterSetName="Default", SupportsShouldProcess = $true)] 
Param(
	[parameter(ValueFromPipeline = $true)]
 	[string]$SqlServer = $env:COMPUTERNAME,
    [ValidateSet(“excel”,”csv”,”clixml”)] 
    [string]$OutputType = "clixml",
    [ValidateScript({Test-Path $_})]
    [string]$OutputLocation = [Environment]::GetFolderPath("mydocuments"),
    [ValidateScript({Test-Path $_})]
    [string]$ScriptLocation = [Environment]::GetFolderPath("mydocuments"),
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

        $scriptfiles = Get-ChildItem "$ScriptLocation\GlennBerryDMV_*_*.sql"

        if (!$scriptfiles)
        {
            Write-Verbose "No files, download?"
            Invoke-DbaGlennBerryDMVDownloadScript -ScriptLocation $ScriptLocation
            $scriptfiles = Get-ChildItem "$ScriptLocation\GlennBerryDMV_*_*.sql"
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
                $script = Invoke-DbaGlennBerryDMVScriptParser -filename $file.fullname
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
        Write-Output "Running Glenn Berry DMV scripts on $($SqlServers.count) server(s), exporting to $OutputType at $OutputLocation" 
        $servercounter = 0
        foreach ($SqlServer in $SqlServers | Select-Object -ExpandProperty SqlServer)
        {
            $servercounter += 1
            $clixml = @()

            $smoSqlServer = Connect-DbaSqlServer -SqlServer $SqlServer

            $out = "Collecting Glenn Berry DMV Data from Server: {0}" -f $SqlServer
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
                $QueryName = Invoke-DbaGlennBerryDMVSelectionHelper $script
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
                        if (!$NoProgressBar){Write-Progress -Id 1 -ParentId 0 -Activity "Collecting DMV Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100)}
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
                                "Excel"  {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Excel -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$")).xlsx -WorkSheetname $($scriptpart.QueryName) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow}
                                "CSV"    {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Csv -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($scriptpart.QueryNr)_$($scriptpart.QueryName.Replace(" ", "_")).csv -NoTypeInformation}
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
                            if (!$NoProgressBar){Write-Progress -Id 0 -Activity "Running Scripts on SQL Server" -Status ("Instance {0} of {1}" -f $servercounter, $sqlservers.count) -CurrentOperation $SqlServer -PercentComplete (($servercounter / $SqlServers.count) * 100)}
                            if (!$NoProgressBar){Write-Progress -Id 1 -ParentId 0 -Activity "Collecting DMV Data" -Status ('Processing {0} of {1}' -f $counter, $scriptcount) -CurrentOperation $scriptpart.Name -PercentComplete (($Counter / $scriptcount) * 100)}
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
                                    "Excel"  {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Excel -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($database.name).xlsx -WorkSheetname $($scriptpart.QueryName) -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow}
                                    "CSV"    {$result | Select-Object * -ExcludeProperty RowError, RowState, Table, ItemArray, HasErrors | Export-Csv -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$"))_$($database.name)_$($scriptpart.QueryNr)_$($scriptpart.QueryName.Replace(" ", "_")).csv -NoTypeInformation}
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
        if ($OutputType -eq "CliXml"){$clixml | Export-Clixml -Path $OutputLocation\GlennBerryDMV_$($sqlserver.Replace("\", "$")).clixml}
        }
    }

}

