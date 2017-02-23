Function Select-DefaultView
{
	<# 
	
	This command enables us to send full on objects to the pipeline without the user seeing it
	
	See it in action in Get-DbaSnapshot and Remove-DbaDatabaseSnapshot
	
	this is all from boe, thanks boe! 
	https://learn-powershell.net/2013/08/03/quick-hits-set-the-default-property-display-in-powershell-on-custom-objects/
	
	#>
	
	[CmdletBinding()]
	param (
		[parameter(ValueFromPipeline = $true)]
		[object[]]$InputObject,
		[string[]]$Property,
		[string[]]$ExcludeProperty
		
	)
	
	Process
	{
		foreach ($Object in $InputObject)
		{
			if ($ExcludeProperty)
			{
				$properties = ($Object.PsObject.Members | Where-Object MemberType -ne 'Method' | Where-Object { $_.Name -notin $ExcludeProperty }).Name
				$defaultset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$properties)
			}
			else
			{
				# property needs to be string
				if ("$property" -like "* as *")
				{
					$newproperty = @()
					foreach ($p in $property)
					{
						if ($p -like "* as *")
						{
							$old, $new = $p -isplit " as "
							$Object | Add-Member -MemberType AliasProperty -Name $new -Value $old -Force
							$newproperty += $new
						}
						else
						{
							$newproperty += $p
						}
					}
					$property = $newproperty
				}
				
				$defaultset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$Property)
			}
			
			$standardmembers = [System.Management.Automation.PSMemberInfo[]]@($defaultset)
			$Object | Add-Member MemberSet PSStandardMembers $standardmembers -Force
			$Object
		}
	}
}