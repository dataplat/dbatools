Function ConvertFrom-SecurePass {
    # Decrypt passwords on Linux, Windows and OSX
    #https://github.com/PowerShell/PowerShell/issues/13494#issuecomment-678150857
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [System.Security.SecureString]$InputObject
    )
    process {
        (New-Object PSCredential -ArgumentList "fake", $InputObject).GetNetworkCredential().Password
    }
}