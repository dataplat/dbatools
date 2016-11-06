function Export-DbaAvailabilityGroup
{
<#
.SYNOPSIS
Export SQL Server Availability Groups to a T-SQL file. 

.DESCRIPTION
Export SQL Server Availability Groups to a T-SQL file. This includes all replicas, all databases in the AG and the listener creation. This is a function that is not available in SSMS.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
The SQL Server instance name. SQL Server 2012 and above supported.

.PARAMETER OutputFileLocation
The directory name where the output files will be written. Output file format will be "ServerName_InstanceName_AGName.sql"

.PARAMETER AppendDateToOutputFilename
This will automatically append the current date/time to the export files. Using this parameter will change the output file name format to "ServerName_InstanceName_AGName_DateTime.sql"

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
Export-DbaAvailabilityGroup -SqlServer sql2012 -OutputFileLocation 'C:\temp\availability_group_exports'

Exports Availability Group T-SQL scripts for SQL server "sql2012" and writes them to the C:\temp\availability_group_exports directory.

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sql2014 -OutputFileLocation 'C:\temp\availability_group_exports' -NoClobber

Exports Availability Group T-SQL scripts for SQL server "sql2014" and writes them to the C:\temp\availability_group_exports directory. Do not overwrite

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
		    [string]$OutputFileLocation,

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
        $AllAGs =  $SQLObj.AvailabilityGroups
       
        if (($AvailabilityGroups.count) -gt 0) { 
            Write-Output "Applying filter for following Availability Groups:"
            $AvailabilityGroups | Out-String | Write-Output $_
            $AllAGs = $AllAGs | Where-Object {$_.name -in $AvailabilityGroups} 
        }

        if ($AllAGs.count -eq 0) {
            Write-Output "No Availability Groups detected on '$SqlServer'"
        }

        foreach ($ag in $AllAGs) {
            $SQLINST = $SQLServer.Replace('\','_')
            $AGName = $ag.Name

            # Set the outfile name
            if ($AppendDateToOutputFilename.IsPresent) {
                $Dttm = (Get-Date -Format 'yyyyMMdd_hhmm')
                $OutFile = "${OutputFileLocation}\${SQLINST}\${AGname}_${Dttm}.sql"
            } else {
                $OutFile = "${OutputFileLocation}\${SQLINST}\${AGname}.sql"
            }

            if (!(Test-Path -Path $OutFile -PathType Leaf)) {
                New-Item -Path $OutFile -ItemType File -Force
            }
            Write-output "Scripting Availability Group [$AGName] to '$OutFile'"

            '/*' | Out-File -OutputFileLocation $OutFile -Encoding ASCII -Force
            $ag | Select-Object -Property * | Out-File -OutputFileLocation $OutFile -Encoding ASCII -Append
            '*/' | Out-File -OutputFileLocation $OutFile -Encoding ASCII -Append

            $ag.Script() | Out-File -OutputFileLocation $OutFile -Encoding ASCII -Append
        }
    }

    END
    {
		$SQLObj.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Completed Export-DbaAvailabilityGroup" }
    }
}