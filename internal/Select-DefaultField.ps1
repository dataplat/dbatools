Function Select-DefaultField
{
	<# 
	
	This command enables us to send full on objects to the pipeline without the user seeing it
	
	See it in action in Get-DbaSnapshot and Remove-DbaDatabaseSnapshot
	
	this is all from boe, thanks boe! 
	https://learn-powershell.net/2013/08/03/quick-hits-set-the-default-property-display-in-powershell-on-custom-objects/
	
	#>
	
	[CmdletBinding()]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[pscustomobject]$InputObject,
		[parameter(Mandatory = $true)]
		[string[]]$Property
	)
	
	$inputobject.PSObject.TypeNames.Insert(0, 'dbatools.customobject')
	$defaultset = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$Property)
	$standardmembers = [System.Management.Automation.PSMemberInfo[]]@($defaultset)
	$inputobject | Add-Member MemberSet PSStandardMembers $standardmembers
	$inputobject
}