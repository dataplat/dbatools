function Convert-HexStringToByte {
    <#
    .SYNOPSIS
    Converts hex string into byte object

    .DESCRIPTION
    Converts hex string (e.g. '0x01641736') into the byte object ([byte[]]@(1,100,23,54))
    Used when working with SMO logins and their byte parameters: sids and hashed passwords

    .PARAMETER InputObject
    Input hex string (e.g. '0x1234' or 'DBA2FF')

    .NOTES
    Tags: Login, Internal
    Author: Kirill Kravtsov (@nvarscar)
    dbatools PowerShell module (https://dbatools.io)
   Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
    Convert-HexStringToByte '0x01641736'

    Returns byte[] object [byte[]]@(1,100,23,54)

    .EXAMPLE
    Convert-HexStringToByte '1234'

    Returns byte[] object [byte[]]@(18,52)
    #>
    param (
        [string]$InputObject
    )
    $hexString = $InputObject.TrimStart("0x")
    if ($hexString.Length % 2 -eq 1) { $hexString = '0' + $hexString }
    [byte[]]$outByte = $null; $outByte += 0 .. (($hexString.Length) / 2 - 1) | ForEach-Object { [Int16]::Parse($hexString.Substring($_ * 2, 2), 'HexNumber') }
    Return $outByte
}