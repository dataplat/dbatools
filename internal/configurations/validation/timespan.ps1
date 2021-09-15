Register-DbatoolsConfigValidation -Name "timespan" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [timespan]$timespan = $Value }
    catch {
        $Result.Message = "Not a Timespan: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $timespan

    return $Result
}