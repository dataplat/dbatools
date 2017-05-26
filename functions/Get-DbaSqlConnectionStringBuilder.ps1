Function Get-DbaSqlConnectionStringBuilder
{
<#
.SYNOPSIS
Returns a System.Data.SqlClient.SqlConnectionStringBuilder with the string specified

.DESCRIPTION
Creates a System.Data.SqlClient.SqlConnectionStringBuilder from a connection string.

.PARAMETER ConnectionString
A Connection String

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
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [string[]]$Connectiontring = $null
	)
    process {
        New-Object Data.SqlClient.SqlConnectionStringBuilder $Connectiontring
    }
}