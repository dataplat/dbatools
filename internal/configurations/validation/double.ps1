Register-DbatoolsConfigValidation -Name "double" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSOBject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [double]$number = $Value }
    catch {
        $Result.Message = "Not a double: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $number

    return $Result
}