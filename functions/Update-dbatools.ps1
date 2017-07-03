Function Update-DbaTools
{
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
param(
	[parameter(Mandatory=$false)]
	[Alias("dev","devbranch")]
	[switch]$Development
)
<#
.SYNOPSIS
Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

.DESCRIPTION
Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

.PARAMETER Development
Installs the current development branch of dbatools instead of the latest release.

.NOTES 
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
https://dbatools.io/Update-dbatools

.EXAMPLE
Update-DbaTools

Updates dbatools. Deletes current copy and replaces it with freshest copy.

.EXAMPLE
Update-DbaTools -dev

Updates dbatools to the current development branch. Deletes current copy and replaces it with latest from github

#>	
	$MyModuleBase = (Get-Module -name dbatools).ModuleBase;
	$InstallScript = join-path -path $MyModuleBase -ChildPath "install.ps1";
	if($Development) {
		Write-Verbose "Installing dev/beta channel via $Installscript";
		if ($PSCmdlet.ShouldProcess("development branch","Updating dbatools")) {
			& $InstallScript -beta;
		}
	}
	else {
		Write-Verbose "Installing release version via $Installscript"
		if ($PSCmdlet.ShouldProcess("release branch","Updating dbatools")) {
			& $InstallScript;
		}
	}
}
