Function Update-DbaTools {
	<#
		.SYNOPSIS
			Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

		.DESCRIPTION
			Exported function. Updates dbatools. Deletes current copy and replaces it with freshest copy.

		.PARAMETER Development
			If this switch is enabled, the current development branch will be installed. By default, the latest official release is installed.

		.PARAMETER WhatIf
			If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

		.PARAMETER Confirm
			If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

		.NOTES 
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Update-DbaTools

		.EXAMPLE
			Update-DbaTools

			Updates dbatools. Deletes current copy and replaces it with freshest copy.

		.EXAMPLE
			Update-DbaTools -dev

			Updates dbatools to the current development branch. Deletes current copy and replaces it with latest from github.
	#>	
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact="Low")]
param(
	[parameter(Mandatory=$false)]
	[Alias("dev","devbranch")]
	[switch]$Development
)
	$MyModuleBase = (Get-Module -name dbatools).ModuleBase;
	$InstallScript = join-path -path $MyModuleBase -ChildPath "install.ps1";
	if($Development) {
		Write-Verbose "Installing dev/beta channel via $Installscript.";
		if ($PSCmdlet.ShouldProcess("development branch","Updating dbatools")) {
			& $InstallScript -beta;
		}
	}
	else {
		Write-Verbose "Installing release version via $Installscript."
		if ($PSCmdlet.ShouldProcess("release branch","Updating dbatools")) {
			& $InstallScript;
		}
	}
}
