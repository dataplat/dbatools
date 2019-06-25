Register-DbatoolsConfigValidation -Name "string" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try {
        # Seriously, this should work for almost anybody and anything
        [string]$data = $Value
    } catch {
        $Result.Message = "Not a string: $Value"
        $Result.Success = $False
        return $Result
    }

    if ([string]::IsNullOrEmpty($data)) {
        $Result.Message = "Is an empty string: $Value"
        $Result.Success = $False
        return $Result
    }

    if ($data -eq $Value.GetType().FullName) {
        $Result.Message = "Is an object with no proper string representation: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $data

    return $Result
}