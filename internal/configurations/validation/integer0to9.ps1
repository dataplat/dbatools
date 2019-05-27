Register-DbatoolsConfigValidation -Name "integer0to9" -ScriptBlock {
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

    if (($number -lt 0) -or ($number -gt 9)) {
        $Result.Message = "Out of range. Specify a number ranging from 0 to 9"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $Number

    return $Result
}