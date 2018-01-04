Register-DbaConfigValidation -Name "consolecolor" -ScriptBlock {
    Param (
        $Value
    )

    $Result = New-Object PSObject -Property @{
        Success = $True
        Value   = $null
        Message = ""
    }

    try { [System.ConsoleColor]$color = $Value }
    catch {
        $Result.Message = "Not a console color: $Value"
        $Result.Success = $False
        return $Result
    }

    $Result.Value = $color

    return $Result
}