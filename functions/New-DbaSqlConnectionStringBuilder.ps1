Function New-DbaSqlConnectionStringBuilder
{
<#
.SYNOPSIS
Returns a System.Data.SqlClient.SqlConnectionStringBuilder with the string specified

.DESCRIPTION
Creates a System.Data.SqlClient.SqlConnectionStringBuilder from a connection string.

.PARAMETER ConnectionString
A Connection String

.PARAMETER ApplicationName
The application name to tell SQL Server the connection is associated with.

.PARAMETER DataSource
The Sql Server to connect to.

.PARAMETER InitialCatalog
The initial database on the server to connect to.

.PARAMETER IntegratedSecurity
Set to true to use windows authentication.

.PARAMETER SqlUser
Sql User Name to connect with.

.PARAMETER Password
Password to use to connect withy.

.NOTES
Author: zippy1981
Tags: SqlBuild

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Get-DbaSqlConnectionStringBuilder

.EXAMPLE
Get-DbaSqlConnectionStringBuilder

Returns an empty ConnectionStringBuilder

.EXAMPLE
"Data Source=localhost,1433;Initial Catalog=AlwaysEncryptedSample;UID=sa;PWD=alwaysB3Encrypt1ng;Application Name=Always Encrypted Sample MVC App;Column Encryption Setting=enabled" | Get-DbaSqlConnectionStringBuilder 

Returns a connection string builder that can be used to connect to the local sql server instance on the default port.

#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string[]]$ConnectionString = "",
		[Parameter(Mandatory = $false)]
		[string]$ApplicationName = "dbatools Powershell Module",
		[Parameter(Mandatory = $false)]
		[string]$DataSource = $null,
		[Parameter(Mandatory = $false)]
		[string]$InitialCatalog = $null,
		[Parameter(Mandatory = $false)]
		[Nullable[bool]]$IntegratedSecurity = $null,
		[Parameter(Mandatory = $false)]
		[string]$SqlUser = $null,
		# No point in securestring here, the memory is never stored securely in memory.
		[Parameter(Mandatory = $false)]
		[string]$Password = $null
	)
    process {
		foreach ($string in $ConnectionString) {
			$builder = New-Object Data.SqlClient.SqlConnectionStringBuilder $ConnectionString
			if ($builder.ApplicationName -eq ".Net SqlClient Data Provider") {
				$builder['Application Name'] = $ApplicationName
			}
			if ($DataSource -ne $null) {
				$builder['Data Source'] = $DataSource
			}
			if ($InitialCatalog -ne $null) {
				$builder['Initial Catalog'] = $InitialCatalog
			}
			if ($IntegratedSecurity -ne $null) {
				$builder['Integrated Security'] = $IntegratedSecurity
			}
			<#
			if ($SqlUser -ne $null) {
				$builder['User ID'] = $SqlUser
			}
			if ($Password -ne $null) {
				$builder['Password'] = $Password
			}
			#>
			$builder
		}
    }
}