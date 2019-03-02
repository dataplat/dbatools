Register-DbatoolsConfigValidation -Name "datetime" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [DateTime]$DateTime = $Value }
    catch {
        $Result.Message = "Not a DateTime: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $DateTime

    return $Result
}