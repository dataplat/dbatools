Register-DbatoolsConfigValidation -Name "integerpositive" -ScriptBlock {
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

    if ($number -lt 0) {
        $Result.Message = "Negative value: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $number

    return $Result
}