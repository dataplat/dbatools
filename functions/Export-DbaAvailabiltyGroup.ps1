function Export-DbaAvailabilityGroup
{
<#
.SYNOPSIS
Export SQL Server Availability Groups to a T-SQL file. 

.DESCRIPTION
Export SQL Server Availability Groups to a T-SQL file. This includes all replicas, all databases in the AG and the listener creation. This is a function that is not available in SSMS.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
The SQL Server instance name. SQL Server 2012 and above supported

.PARAMETER FilePath
The directory name where the output files will be written. Output file format will be "ServerName_InstanceName_AGName.sql"

.PARAMETER AppendDateToOutputFilename
This will automatically append the current date/time to the export files. Using this parameter will change the output file name format to "ServerName_InstanceName_AGName_DateTime.sql"

.PARAMETER Include
An array containint Availability Group names to include

.PARAMETER Exclude
An array containint Availability Group names to exclude

.PARAMETER NoClobber
Do not overwrite existing export files.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER AvailabilityGroups
Allows you to specify which Availability Groups to export. (Dynamic Param)

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Export-DbaAvailabilityGroup

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sql2012 -FilePath 'C:\temp\availability_group_exports'

Exports all Availability Groups from SQL server "sql2012". Output scripts are witten to the C:\temp\availability_group_exports directory.

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sql2012 -FilePath 'C:\temp\availability_group_exports' -Include AG1,AG2

Exports Availability Groups AG1 and AG2 from SQL server "sql2012". Output scripts are witten to the C:\temp\availability_group_exports directory.

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sql2014 -FilePath 'C:\temp\availability_group_exports' -NoClobber

Exports all Availability Groups from SQL server "sql2014". Output scripts are witten to the C:\temp\availability_group_exports directory. If the export file already exists it will not be overwritten.

.NOTES 
Author: Chris Sommer (@cjsommer), cjsommmer.com

.LINK 
https://dbatools.io/Export-DbaAvailabilityGroup

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
	Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		    [Alias("ServerInstance", "SqlInstance")]
		    [object[]]$SqlServer,

		[Alias("OutputLocation", "Path")]
		    [string]$FilePath,

        [array]$Include ,

        [array]$Exclude ,

        [Alias("AppendDttm")]
            [switch]$AppendDateToOutputFilename ,

        [switch]$NoClobber ,

		[object]$SqlCredential
	)

	DynamicParam { if ($sqlserver) { return Get-ParamSqlAvailabilityGroups -SqlServer $sqlserver[0] -SqlCredential $SqlCredential } }
	
    BEGIN
    {
        Write-Output "Beginning Export-DbaAvailabilityGroup"
        $SQLObj = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SQLServer
        $SQLObj.ConnectionContext.Connect()
    }

    PROCESS
    {
        # Get all of the Availability Groups and filter if required
        $AllAGs =  $SQLObj.AvailabilityGroups

        if ($Include) { 
            Write-Verbose "Applying INCLUDE filter"
            $AllAGs = $AllAGs | Where-Object {$_.name -in $Include} 
        }

        if ($Exclude) {
            Write-Verbose "Applying EXCLUDE filter"
            $AllAGs = $AllAGs | Where-Object {$_.name -notin $Exclude} 
        }

        if ($AllAGs.count -eq 0) {
            Write-Verbose "No Availability Groups detected on '$SqlServer'"
        }

        # Set and create the OutputLocation if it doesn't exist
        $SQLINST = $SQLServer.Replace('\','$')
        $OutputLocation = "${FilePath}\${SQLINST}"

        if (!(Test-Path $OutputLocation -PathType Container)) {
            New-Item -Path $OutputLocation -ItemType Directory -Force | Out-Null
        } 

        # Script each Availability Group
        foreach ($ag in $AllAGs) {
            $AGName = $ag.Name

            # Set the outfile name
            if ($AppendDateToOutputFilename.IsPresent) {
                $Dttm = (Get-Date -Format 'yyyyMMdd_hhmm')
                $OutFile = "${OutputLocation}\${AGname}_${Dttm}.sql"
            } else {
                $OutFile = "${OutputLocation}\${AGname}.sql"
            }

            # Check NoClobber and script out the AG
            if ($NoClobber.IsPresent -and (Test-Path -Path $OutFile -PathType Leaf)) {
                Write-Warning "OutputFile '$OutFile' already exists. Skipping due to -NoClobber parameter"
            } else {
                Write-output "Scripting Availability Group [$AGName] to '$OutFile'"

                '/*' | Out-File -FilePath $OutFile -Encoding ASCII -Force
                $ag | Select-Object -Property * | Out-File -FilePath $OutFile -Encoding ASCII -Append
                '*/' | Out-File -FilePath $OutFile -Encoding ASCII -Append

                $ag.Script() | Out-File -FilePath $OutFile -Encoding ASCII -Append
            }
        }
    }

    END
    {
		$SQLObj.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Completed Export-DbaAvailabilityGroup" }
    }
}