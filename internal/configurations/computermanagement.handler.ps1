#region ComputerManagement.Cache.Disable.All
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableCache = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Disable.All' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Disable.All

#region ComputerManagement.Cache.Disable.BadCredentialList
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableBadCredentialCache = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Disable.BadCredentialList' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Disable.BadCredentialList

#region ComputerManagement.Cache.Disable.CredentialAutoRegister
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableCredentialAutoRegister = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Disable.CredentialAutoRegister' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Disable.CredentialAutoRegister

#region ComputerManagement.Cache.Force.OverrideExplicitCredential
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::OverrideExplicitCredential = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Force.OverrideExplicitCredential' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Force.OverrideExplicitCredential

#region ComputerManagement.BadConnectionTimeout
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.TimeSpan")
    {
        $Result.Message = "Not a TimeSpan: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::BadConnectionTimeout = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.BadConnectionTimeout' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.BadConnectionTimeout

#region ComputerManagement.Cache.Disable.CimPersistence
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableCimPersistence = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Disable.CimPersistence' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Disable.CimPersistence

#region ComputerManagement.Cache.Enable.CredentialFailover
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    if ($Value.GetType().FullName -ne "System.Boolean")
    {
        $Result.Message = "Not a Boolean: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [Sqlcollaborative.Dbatools.Connection.ConnectionHost]::EnableCredentialFailover = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Cache.Enable.CredentialFailover' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Cache.Enable.CredentialFailover

#region ComputerManagement.Type.Disable.CimRM
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success  = $True
		Message  = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableConnectionCimRM = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Type.Disable.CimRM' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Type.Disable.CimRM

#region ComputerManagement.Type.Disable.CimDCOM
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success  = $True
		Message  = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableConnectionCimDCOM = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Type.Disable.CimDCOM' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Type.Disable.CimDCOM

#region ComputerManagement.Type.Disable.WMI
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success  = $True
		Message  = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableConnectionWMI = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Type.Disable.WMI' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Type.Disable.WMI

#region ComputerManagement.Type.Disable.PowerShellRemoting
$ScriptBlock = {
	Param (
		$Value
	)
	
	$Result = New-Object PSOBject -Property @{
		Success  = $True
		Message  = ""
	}
	
	if ($Value.GetType().FullName -ne "System.Boolean") {
		$Result.Message = "Not a Boolean: $Value"
		$Result.Success = $False
		return $Result
	}
	
	[Sqlcollaborative.Dbatools.Connection.ConnectionHost]::DisableConnectionPowerShellRemoting = $Value
	
	return $Result
}
Register-DbaConfigHandler -Name 'ComputerManagement.Type.Disable.PowerShellRemoting' -ScriptBlock $ScriptBlock
#endregion ComputerManagement.Type.Disable.PowerShellRemoting
