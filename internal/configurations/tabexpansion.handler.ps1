#region TabExpansion.Disable
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success = $True
		Message = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled = $Value
	
	# Disable Async TEPP runspace if not needed
	if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled) {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Stop()
	}
	else {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Start()
	}
	
	return $Result
}
Register-DbaConfigHandler -Name 'TabExpansion.Disable' -ScriptBlock $ScriptBlock
#endregion TabExpansion.Disable

#region TabExpansion.Disable.Asynchronous
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success = $True
		Message = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled = $Value
	
	# Disable Async TEPP runspace if not needed
	if ([Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppAsyncDisabled -or [Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppDisabled) {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Stop()
	}
	else {
		[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::Start()
	}
	
	return $Result
}
Register-DbaConfigHandler -Name 'TabExpansion.Disable.Asynchronous' -ScriptBlock $ScriptBlock
#endregion TabExpansion.Disable.Asynchronous

#region TabExpansion.Disable.Synchronous
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success = $True
		Message = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppSyncDisabled = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'TabExpansion.Disable.Synchronous' -ScriptBlock $ScriptBlock
#endregion TabExpansion.Disable.Synchronous

#region TabExpansion.UpdateInterval
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success = $True
		Message = ""
	}
	
	if ($Value.GetType().FullName -ne "System.TimeSpan") {
		$Result.Message = "Not a TimeSpan: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateInterval = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'TabExpansion.UpdateInterval' -ScriptBlock $ScriptBlock
#endregion TabExpansion.UpdateInterval

#region TabExpansion.UpdateTimeout
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success = $True
		Message = ""
	}
	
	if ($Value.GetType().FullName -ne "System.TimeSpan") {
		$Result.Message = "Not a TimeSpan: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.TabExpansion.TabExpansionHost]::TeppUpdateTimeout = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'TabExpansion.UpdateTimeout' -ScriptBlock $ScriptBlock
#endregion TabExpansion.UpdateInterval
