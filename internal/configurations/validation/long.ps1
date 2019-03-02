Register-DbatoolsConfigValidation -Name "long" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSOBject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [long]$number = $Value }
    catch {
        $Result.Message = "Not a long: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $number

    return $Result
}