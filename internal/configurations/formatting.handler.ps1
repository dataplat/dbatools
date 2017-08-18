#region Formatting.Date
$ScriptBlock = {
    Param (
        [string]
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    
    
    if ([string]::IsNullOrEmpty($Value))
    {
        $Result.Message = "Is an empty format string! Must specify something."
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.Utility.UtilityHost]::FormatDate = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Formatting.Date' -ScriptBlock $ScriptBlock
#endregion Formatting.Date

#region Formatting.DateTime
$ScriptBlock = {
    Param (
        [string]
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    
    
    if ([string]::IsNullOrEmpty($Value))
    {
        $Result.Message = "Is an empty format string! Must specify something."
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.Utility.UtilityHost]::FormatDateTime = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Formatting.DateTime' -ScriptBlock $ScriptBlock
#endregion Formatting.DateTime

#region Formatting.Time
$ScriptBlock = {
    Param (
        [string]
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    
    
    if ([string]::IsNullOrEmpty($Value))
    {
        $Result.Message = "Is an empty format string! Must specify something."
        $Result.Success = $False
        return $Result
    }
    
    [sqlcollective.dbatools.Utility.UtilityHost]::FormatTime = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Formatting.Time' -ScriptBlock $ScriptBlock
#endregion Formatting.Time

#region Formatting.Disable.CustomDateTime
$ScriptBlock = {
    Param (
        [bool]
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    [Sqlcollective.Ddbatools.Utility.UtilityHost]::DisableCustomDateTime = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Formatting.Disable.CustomDateTime' -ScriptBlock $ScriptBlock
#endregion Formatting.Disable.CustomDateTime

#region Formatting.Disable.CustomTimeSpan
$ScriptBlock = {
    Param (
        [bool]
        $Value
    )
    
    $Result = New-Object PSOBject -Property @{
        Success = $True
        Message = ""
    }
    
    [Sqlcollective.Ddbatools.Utility.UtilityHost]::DisableCustomTimeSpan = $Value
    
    return $Result
}
Register-DbaConfigHandler -Name 'Formatting.Disable.CustomTimeSpan' -ScriptBlock $ScriptBlock
#endregion Formatting.Disable.CustomTimeSpan