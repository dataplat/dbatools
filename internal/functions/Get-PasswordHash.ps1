function Get-PasswordHash {
    <#
    .SYNOPSIS
    Generates a password hash for SQL Server login

    .DESCRIPTION
    Generates a hash string based on the plaintext or securestring password and a SQL Server version. Salt is optional

    .PARAMETER Password
    Either plain text or Securestring password

    .PARAMETER SqlMajorVersion
    Major version of the SQL Server. Defines the hash algorithm.

    .PARAMETER byteSalt
    Optional. Inserts custom salt into the hash instead of randomly generating new salt

    .NOTES
    Tags: Login, Internal
    Author: Kirill Kravtsov (@nvarscar)
    dbatools PowerShell module (https://dbatools.io)
   Copyright: (c) 2018 by dbatools, licensed under MIT
    License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
    Get-PasswordHash $securePassword 11

    Generates password hash for SQL 2012

    .EXAMPLE
    Get-PasswordHash $securePassword 9 $byte

    Generates password hash for SQL 2005 using custom salt from the $byte variable

    #>
    param (
        [object]$Password,
        $SqlMajorVersion,
        [byte[]]$byteSalt
    )
    #Choose hash algorithm
    if ($SqlMajorVersion -lt 11) {
        $algorithm = 'SHA1'
        $hashVersion = '0100'
    } else {
        $algorithm = 'SHA512'
        $hashVersion = '0200'
    }

    #Generate salt
    if (!$byteSalt) {
        0 .. 3 | ForEach-Object { $byteSalt += Get-Random -Minimum 0 -Maximum 255 }
    }

    #Convert salt to a hex string
    [string]$stringSalt = ""
    $byteSalt | ForEach-Object { $stringSalt += ("{0:X}" -f $_).PadLeft(2, "0") }

    #Extract password
    if ($Password.GetType().Name -eq 'SecureString') {
        $cred = New-Object System.Management.Automation.PSCredential -ArgumentList 'foo', $Password
        $plainPassword = $cred.GetNetworkCredential().Password
    } else {
        $plainPassword = $Password
    }
    #Get byte representation of the password string
    $enc = [system.Text.Encoding]::Unicode
    $data = $enc.GetBytes($plainPassword)
    #Run hash algorithm
    $hash = [Security.Cryptography.HashAlgorithm]::Create($algorithm)
    $bytes = $hash.ComputeHash($data + $byteSalt)
    #Construct hex string
    $hashString = "0x$hashVersion$stringSalt"
    $bytes | ForEach-Object { $hashString += ("{0:X2}" -f $_).PadLeft(2, "0") }
    #Add UPPERCASE hash for SQL 2000 and lower
    if ($SqlMajorVersion -lt 9) {
        $data = $enc.GetBytes($plainPassword.ToUpper())
        $bytes = $hash.ComputeHash($data + $byteSalt)
        $bytes | ForEach-Object { $hashString += ("{0:X2}" -f $_).PadLeft(2, "0") }
    }
    return $hashString
}