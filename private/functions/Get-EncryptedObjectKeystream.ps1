function Get-EncryptedObjectKeystream {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Returns the keystream that obfuscates the stored definition of a module created WITH ENCRYPTION.

        WITH ENCRYPTION is a reversible XOR obfuscation rather than encryption. SQL Server stores the
        definition text as UCS-2 XORed with an RC4 keystream, and the RC4 key is derived only from
        metadata that a sysadmin can already read, so there is no secret involved:

            key       = SHA1(familyGuid(16 bytes) + objectId(4 bytes LE) + colId(2 bytes LE))
            keystream = RC4(key)
            plaintext = ciphertext XOR keystream

        The keystream is specific to the object id, so two objects with identical source text produce
        different ciphertext. Because RC4 is a stream cipher the keystream depends only on the key and
        not on the data, so exactly as many bytes as the ciphertext are generated.

        This function is used by the following public functions:
        - Invoke-DbaDbDecryptObject

    .PARAMETER FamilyGuid
        The family GUID of the database that holds the object, as reported by family_guid of the catalog view
        sys.database_recovery_status. One value per database, stable for the life of the database.

    .PARAMETER ObjectId
        The object id of the encrypted object.

    .PARAMETER ColId
        The subobjid of the sys.sysobjvalues row that holds this chunk of ciphertext. Almost always 1.

    .PARAMETER Length
        The number of keystream bytes to generate, which is the length of the ciphertext.

    .NOTES
        Tags: Encryption, Decrypt
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        Get-EncryptedObjectKeystream -FamilyGuid $familyGuid -ObjectId 1253579504 -ColId 1 -Length 128

        Returns the 128 keystream bytes that decrypt the first chunk of object 1253579504.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [guid]$FamilyGuid,
        [Parameter(Mandatory)]
        [int]$ObjectId,
        [Parameter(Mandatory)]
        [int]$ColId,
        [Parameter(Mandatory)]
        [int]$Length
    )

    # The RC4 key is a SHA1 over 22 bytes of public metadata. The GUID has to be laid out in the byte
    # order that System.Guid uses, where the first three fields are little endian. The string order of
    # the GUID does not produce a working key.
    $seed = New-Object byte[] 22
    [Array]::Copy($FamilyGuid.ToByteArray(), 0, $seed, 0, 16)
    [Array]::Copy([BitConverter]::GetBytes([int]$ObjectId), 0, $seed, 16, 4)
    [Array]::Copy([BitConverter]::GetBytes([int16]$ColId), 0, $seed, 20, 2)

    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $key = $sha1.ComputeHash($seed)
    } finally {
        $sha1.Dispose()
    }

    # RC4 key scheduling algorithm.
    $state = New-Object byte[] 256
    for ($i = 0; $i -lt 256; $i++) {
        $state[$i] = [byte]$i
    }

    $j = 0
    for ($i = 0; $i -lt 256; $i++) {
        $j = ($j + $state[$i] + $key[$i % $key.Length]) -band 0xFF
        $swap = $state[$i]
        $state[$i] = $state[$j]
        $state[$j] = $swap
    }

    # RC4 pseudo random generation algorithm, one keystream byte per ciphertext byte.
    $keystream = New-Object byte[] $Length
    $x = 0
    $y = 0
    for ($k = 0; $k -lt $Length; $k++) {
        $x = ($x + 1) -band 0xFF
        $y = ($y + $state[$x]) -band 0xFF
        $swap = $state[$x]
        $state[$x] = $state[$y]
        $state[$y] = $swap
        $keystream[$k] = $state[([int]$state[$x] + [int]$state[$y]) -band 0xFF]
    }

    # -NoEnumerate keeps PowerShell from unrolling the byte array into the pipeline, so the caller
    # receives one byte[] rather than a stream of separate bytes.
    Write-Output -NoEnumerate $keystream
}
