Register-DbatoolsConfigValidation -Name "bool" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if ($Value.GetType().FullName -ne "System.Boolean") {
            $Result.Message = "Not a boolean: $Value"
            $Result.Success = $False
            return $Result
        }
    } catch {
        $Result.Message = "Not a boolean: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $Value

    return $Result
}