Register-DbatoolsConfigValidation -Name "securestring" -ScriptBlock {
    param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }
    try {
        if ($Value.GetType().FullName -ne "System.Security.SecureString") {
            $Result.Message = "Not a securestring: $Value"
            $Result.Success = $False
            return $Result
        }
    } catch {
        $Result.Message = "Not a securestring: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $Value

    return $Result
}