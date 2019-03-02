Register-DbatoolsConfigValidation -Name "integer" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSOBject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [int]$number = $Value }
    catch {
        $Result.Message = "Not an integer: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $number

    return $Result
}