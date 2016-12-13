function Export-DbaAvailabilityGroup
{
<#
.SYNOPSIS
Export SQL Server Availability Groups to a T-SQL file. 

.DESCRIPTION
Export SQL Server Availability Groups creation scripts to a T-SQL file. This is a function that is not available in SSMS.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
The SQL Server instance name. SQL Server 2012 and above supported.

.PARAMETER FilePath
The directory name where the output files will be written. A sub directory with the format 'ServerName$InstanceName' will be created. A T-SQL scripts named 'AGName.sql' will be created under this subdirectory for each scripted Availability Group.

.PARAMETER AvailabilityGroups
Specify which Availability Groups to export (Dynamic Param)

.PARAMETER NoClobber
Do not overwrite existing export files.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

.PARAMETER WhatIf
Shows you what it'd output if you were to run the command
	
.PARAMETER Confirm
Confirms each step/line of output
	
.NOTES 
Author: Chris Sommer (@cjsommer), cjsommmer.com

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
Export-DbaAvailabilityGroup -SqlServer sql2012 -FilePath 'C:\temp\availability_group_exports' -AvailabilityGroups AG1,AG2

Exports Availability Groups AG1 and AG2 from SQL server "sql2012". Output scripts are witten to the C:\temp\availability_group_exports directory.

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sql2014 -FilePath 'C:\temp\availability_group_exports' -NoClobber

Exports all Availability Groups from SQL server "sql2014". Output scripts are witten to the C:\temp\availability_group_exports directory. If the export file already exists it will not be overwritten.

.LINK 
https://dbatools.io/Export-DbaAvailabilityGroup

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
	Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		    [Alias("ServerInstance", "SqlInstance")]
		    [object[]]$SqlServer,

		[System.Management.Automation.PSCredential]$SqlCredential,

		[Alias("OutputLocation", "Path")]
		    [string]$FilePath,

        [switch]$NoClobber
	)

	DynamicParam { if ($SqlServer) { return Get-ParamSqlAvailabilityGroups -SqlServer $SqlServer -SqlCredential $SqlCredential } }
	
    BEGIN
    {       
        Write-Output "Beginning Export-DbaAvailabilityGroup on '$SqlServer'" 
        $AvailabilityGroups = $PSBoundParameters.AvailabilityGroups
        
        Write-Verbose "Connecting to SqlServer '$SqlServer'"

        try {
            $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        } catch {
            if ($server.count -eq 1) {
                throw $_
            } else {
                Write-Warning "Can't connect to $SqlServer. Moving on."
                Continue
            }
        }   
    }

    PROCESS
    {
        # Get all of the Availability Groups and filter if required
        $AllAGs =  $server.AvailabilityGroups

        if ($AvailabilityGroups) {
            Write-Verbose 'Filtering AvailabilityGroups'
            $AllAGs = $AllAGs | Where-Object {$_.name -in $AvailabilityGroups}
        }

        if ($AllAGs.count -gt 0) {

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
                Write-output "Scripting Availability Group [$AGName] on [$SQLServer] to '$OutFile'"

                # Create comment block header for AG script
                "/*" | Out-File -FilePath $OutFile -Encoding ASCII -Force
                " * Created by dbatools 'Export-DbaAvailabilityGroup' cmdlet on '$(Get-Date)'" | Out-File -FilePath $OutFile -Encoding ASCII -Append
                " * See https://dbatools.io/Export-DbaAvailabilityGroup for more help" | Out-File -FilePath $OutFile -Encoding ASCII -Append

                # Output AG and listener names
                " *" | Out-File -FilePath $OutFile -Encoding ASCII -Append
                " * Availability Group Name: $($ag.name)" | Out-File -FilePath $OutFile -Encoding ASCII -Append
                $ag.AvailabilityGroupListeners | % {" * Listener Name: $($_.name)"} | Out-File -FilePath $OutFile -Encoding ASCII -Append

                # Output all replicas
                " *" | Out-File -FilePath $OutFile -Encoding ASCII -Append
                $ag.AvailabilityReplicas | % {" * Replica: $($_.name)"} | Out-File -FilePath $OutFile -Encoding ASCII -Append

                # Output all databases
                " *" | Out-File -FilePath $OutFile -Encoding ASCII -Append
                $ag.AvailabilityDatabases | % {" * Database: $($_.name)"} | Out-File -FilePath $OutFile -Encoding ASCII -Append

                # $ag | Select-Object -Property * | Out-File -FilePath $OutFile -Encoding ASCII -Append
                
                "*/" | Out-File -FilePath $OutFile -Encoding ASCII -Append

                # Script the AG
                $ag.Script() | Out-File -FilePath $OutFile -Encoding ASCII -Append
            }
        }
        } else {
            Write-Output "No Availability Groups detected on '$SqlServer'"
        }
    }

    END
    {
		$server.ConnectionContext.Disconnect()
		If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Completed Export-DbaAvailabilityGroup on '$SqlServer'" }
    }
}