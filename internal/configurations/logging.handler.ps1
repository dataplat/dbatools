#region Logging.MaxErrorCount
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxErrorCount = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxErrorCount' -ScriptBlock $ScriptBlock
#endregion Logging.MaxErrorCount

#region Logging.MaxMessageCount
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessageCount = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxMessageCount' -ScriptBlock $ScriptBlock
#endregion Logging.MaxMessageCount

#region Logging.MaxMessagefileBytes
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileBytes = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxMessagefileBytes' -ScriptBlock $ScriptBlock
#endregion Logging.MaxMessagefileBytes

#region Logging.MaxMessagefileCount
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxMessagefileCount = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxMessagefileCount' -ScriptBlock $ScriptBlock
#endregion Logging.MaxMessagefileCount

#region Logging.MaxErrorFileBytes
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxErrorFileBytes = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxErrorFileBytes' -ScriptBlock $ScriptBlock
#endregion Logging.MaxErrorFileBytes

#region Logging.MaxTotalFolderSize
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [int]$number = $Value }
    catch
    {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxTotalFolderSize = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxTotalFolderSize' -ScriptBlock $ScriptBlock
#endregion Logging.MaxTotalFolderSize

#region Logging.MaxLogFileAge
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [timespan]$timespan = $Value }
    catch
    {
        $Result.Message = "Not a Timespan: $Value"
        $Result.Success = $False
        return $Result
    }
    
    if ($timespan.TotalMilliseconds -le 0)
    {
        $Result.Message = "Timespan cannot be set to 0 milliseconds or less: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MaxLogFileAge = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MaxLogFileAge' -ScriptBlock $ScriptBlock
#endregion Logging.MaxLogFileAge

#region Logging.MessageLogFileEnabled
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
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MessageLogFileEnabled = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MessageLogFileEnabled' -ScriptBlock $ScriptBlock
#endregion Logging.MessageLogFileEnabled

#region Logging.MessageLogEnabled
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
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::MessageLogEnabled = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.MessageLogEnabled' -ScriptBlock $ScriptBlock
#endregion Logging.MessageLogEnabled

#region Logging.ErrorLogFileEnabled
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
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::ErrorLogFileEnabled = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.ErrorLogFileEnabled' -ScriptBlock $ScriptBlock
#endregion Logging.ErrorLogFileEnabled

#region Logging.ErrorLogEnabled
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
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::ErrorLogEnabled = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Logging.ErrorLogEnabled' -ScriptBlock $ScriptBlock
#endregion Logging.ErrorLogEnabled