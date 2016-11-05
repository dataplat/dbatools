﻿function Export-DbaAvailabilityGroup
{
<#
.SYNOPSIS
Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

.DESCRIPTION
Exports Windows and SQL Logins to a T-SQL file. Export includes login, SID, password, default database, default language, server permissions, server roles, db permissions, db roles.

THIS CODE IS PROVIDED "AS IS", WITH NO WARRANTIES.

.PARAMETER SqlServer
The SQL Server instance name. SQL Server 2000 and above supported.

.PARAMETER FilePath
The file to write to.

.PARAMETER NoClobber
Do not overwrite file
	
.PARAMETER Append
Append to file
	
.PARAMETER Exclude
Excludes specified logins. This list is auto-populated for tab completion.

.PARAMETER Login
Migrates ONLY specified logins. This list is auto-populated for tab completion. Multiple logins allowed.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 

SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.
	
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
Export-DbaAvailabilityGroup -SqlServer sql2005 -FilePath C:\temp\sql2005-logins.sql

Exports SQL for the logins in server "sql2005" and writes them to the file "C:\temp\sql2005-logins.sql"

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sqlserver2014a -Exclude realcajun -SqlCredential $scred -FilePath C:\temp\logins.sql -Append

Authenticates to sqlserver2014a using SQL Authentication. Exports all logins except for realcajun to C:\temp\logins.sql, and appends to the file if it exists. If not, the file will be created.

.EXAMPLE
Export-DbaAvailabilityGroup -SqlServer sqlserver2014a -Login realcajun, netnerds -FilePath C:\temp\logins.sql

Exports ONLY logins netnerds and realcajun fron sqlsever2014a to the file  C:\temp\logins.sql

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net

.LINK 
https://dbatools.io/Export-DbaAvailabilityGroup

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[string]$SqlServer,
		[Alias("OutFile", "Path","FileName")]
		[string]$FilePath,
		[object]$SqlCredential
	)

    DynamicParam { if ($sqlserver) { return Get-ParamSqlAvailabilityGroups -SqlServer $sqlserver[0] -SqlCredential $SqlCredential } }

    $SQLObj = New-Object "Microsoft.SqlServer.Management.Smo.Server" $SQLServer
    $SQLObj.ConnectionContext.Connect()

    foreach ($ag in ($SQLObj.AvailabilityGroups )){
        $SQLINST = $SQLServer.Replace('\','_')
        $AGName = $ag.Name
        $Dttm = (Get-Date -Format 'yyyyMMdd_hhmm')

        $OutFile = "${FilePath}\${SQLINST}\${AGname}_${Dttm}.sql"
        if (!(Test-Path -Path $OutFile -PathType Leaf)) {
            New-Item -Path $OutFile -ItemType File -Force
        }
        Write-output "Scripting Availability Group [$AGName] to '$OutFile'"

        '/*' | Out-File -FilePath $OutFile -Encoding ASCII -Force
        $ag | Select-Object -Property * | Out-File -FilePath $OutFile -Encoding ASCII -Append
        '*/' | Out-File -FilePath $OutFile -Encoding ASCII -Append

        $ag.Script() | Out-File -FilePath $OutFile -Encoding ASCII -Append
    }
}
