function Test-PsVersion {
    <#
        .SYNOPSIS
            Internal tool, used to detect the version of PowerShell

        .DESCRIPTION
            We still support PS3 and as future continues we will have to maintain code base for PS3 and code base for newer versions of PowerShell. This is just easier function to use for validating version of PS with if/else statements

        .PARAMETER Is
            Use to only allow specific version of PowerShell

        .PARAMETER Minimum
            Use to allow for minimum version

        .PARAMETER Maximum
            Use to allow for maximum version

        .EXAMPLE
            PS C:\> if (Test-PsVersion -Is 3) {
            >> #do something
            >> }

            The calling function will only execute code if PS version is 3.0.

        .EXAMPLE
            PS C:\> if (Test-PsVersion -Minimum 4) {
            >> #do something
            >> }

            The calling function will only execute code if PS version is 4.0 or higher.
        .EXAMPLE
            PS C:\> if (Test-PsVersion -Minimum 3 -Maximum 5.1) {
            >> #do something
            >> }

            The calling function will only execute code if PS version is found to be between 3.0 and 5 (could include 5.0 or 5.1).
    #>
    [CmdletBinding()]
    param (
        [float]$Is,
        [float]$Minimum,
        [float]$Maximum
    )

    begin {
        $major = $PSVersionTable.PSVersion.Major
        $minor = $PSVersionTable.PSVersion.Minor
        [float]$detectedVersion = "$major.$minor"
    }
    process {
        $returnIt = $true

        if ($Maximum) {
            $returnIt = $detectedVersion -le $Maximum
        }
        if ($Minimum) {
            $returnIt = $detectedVersion -ge $Minimum
        }
        if ($Is) {
            $returnIt = $detectedVersion -eq $Is
        }

        return $returnIt
    }
}