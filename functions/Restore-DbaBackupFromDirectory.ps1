Function Restore-DbaBackupFromDirectory
{

#>	
	#Requires -Version 3.0
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true)]
		[Alias("ServerInstance","SqlInstance")]
		[string]$SqlServer,
		[parameter(Mandatory = $true)]
		[string]$Path,
		[switch]$NoRecovery,
		[Alias("ReuseFolderStructure")]
		[switch]$ReuseSourceFolderStructure,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[switch]$Force
		
	)
	
	DynamicParam
	{
		
		if ($Path)
		{
			$newparams = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
			$paramattributes = New-Object System.Management.Automation.ParameterAttribute
			$paramattributes.ParameterSetName = "__AllParameterSets"
			$paramattributes.Mandatory = $false
			$systemdbs = @("master", "msdb", "model", "SSIS")
			$dblist = (Get-ChildItem -Path $Path -Directory).Name | Where-Object { $systemdbs -notcontains $_ }
			$argumentlist = @()
			
			foreach ($db in $dblist)
			{
				$argumentlist += [Regex]::Escape($db)
			}
			
			$validationset = New-Object System.Management.Automation.ValidateSetAttribute -ArgumentList $argumentlist
			$combinedattributes = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
			$combinedattributes.Add($paramattributes)
			$combinedattributes.Add($validationset)
			$Databases = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Databases", [String[]], $combinedattributes)
			$Exclude = New-Object -Type System.Management.Automation.RuntimeDefinedParameter("Exclude", [String[]], $combinedattributes)
			$newparams.Add("Databases", $Databases)
			$newparams.Add("Exclude", $Exclude)
			return $newparams
		}
	}
	
	end {
		Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Restore-SqlBackupFromDirectory -CustomMessage "Restore-DbaDatabase works way better. Please use that instead."
	}
}
