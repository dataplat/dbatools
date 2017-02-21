#region Path.DbatoolsLogPath
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [System.IO.Path]::GetFullPath($Value) }
    catch
    {
        $Result.Message = "Illegal path: $Value"
        $Result.Success = $False
        return $Result
    }
    
    if (Test-Path -Path $Value -PathType Leaf)
    {
        $Result.Message = "Is a file, not a folder: $Value"
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.dbaSystem.DebugHost]::LoggingPath = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Path.DbatoolsLogPath' -ScriptBlock $ScriptBlock
#endregion Path.DbatoolsLogPath

#region Path.DbatoolsData
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [System.IO.Path]::GetFullPath($Value) }
    catch
    {
        $Result.Message = "Illegal path: $Value"
        $Result.Success = $False
        return $Result
    }
    
    if (Test-Path -Path $Value -PathType Leaf)
    {
        $Result.Message = "Is a file, not a folder: $Value"
        $Result.Success = $False
        return $Result
    }
    
    return $Result
}
Register-DbaConfigHandler -Name 'Path.DbatoolsData' -ScriptBlock $ScriptBlock
#endregion Path.DbatoolsData

#region Path.DbatoolsTemp
$ScriptBlock = {
    Param (
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    try { [System.IO.Path]::GetFullPath($Value) }
    catch
    {
        $Result.Message = "Illegal path: $Value"
        $Result.Success = $False
        return $Result
    }
    
    if (Test-Path -Path $Value -PathType Leaf)
    {
        $Result.Message = "Is a file, not a folder: $Value"
        $Result.Success = $False
        return $Result
    }
    
    return $Result
}
Register-DbaConfigHandler -Name 'Path.DbatoolsTemp' -ScriptBlock $ScriptBlock
#endregion Path.DbatoolsTemp