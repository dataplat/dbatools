function ConvertFrom-EncryptedObjectChunk {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Turns the ciphertext chunks of one encrypted object into its definition text.

        A definition can in principle span several sys.sysobjvalues rows, one per subobjid, which is why
        the chunks are ordered by colid and concatenated rather than one row being assumed. SQL Server
        appears never to do this in practice, using a single row and letting the off row machinery deal
        with size instead.

        That has a consequence worth being explicit about: no fixture can produce a multi chunk definition,
        so a byte for byte comparison against a created object cannot reach this code with more than one
        chunk. The multi chunk behaviour of this function is covered by its unit tests and by nothing else.

        Three mistakes are easy to make here and all can produce output that looks more trustworthy than it
        is:

        - Concatenating in the order the rows were read rather than in colid order swaps the parts of a
          definition around.
        - Deriving one keystream for the whole object leaves the first chunk readable and everything after
          it mojibake. colid is an input to the key, so every chunk has its own keystream.
        - Accepting the same colid twice can combine the current row with a stale or duplicate physical row.
          The page reader is deliberately defensive, but this is the final boundary before decryption and
          must reject an ambiguous chunk set rather than concatenate both versions.

        This function is used by the following public functions:
        - Invoke-DbaDbDecryptObject

    .PARAMETER FamilyGuid
        The family GUID of the database that holds the object.

    .PARAMETER ObjectId
        The object id of the encrypted object.

    .PARAMETER Chunk
        The ciphertext chunks, as objects with a ColId and a Cipher property. Order does not matter.

    .NOTES
        Tags: Encryption, Decrypt
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        ConvertFrom-EncryptedObjectChunk -FamilyGuid $familyGuid -ObjectId 1253579504 -Chunk $chunk

        Returns the definition text of object 1253579504.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [guid]$FamilyGuid,
        [Parameter(Mandatory)]
        [int]$ObjectId,
        [Parameter(Mandatory)]
        [object[]]$Chunk
    )

    $scriptBuilder = New-Object System.Text.StringBuilder
    $seenColId = New-Object System.Collections.Hashtable

    foreach ($piece in ($Chunk | Sort-Object -Property ColId)) {
        # There is only one sys.sysobjvalues row for a given (object id, colid). Seeing the same colid twice
        # means the input is ambiguous, for example because a stale physical row was harvested along with
        # the current one. Concatenating both can still yield plausible text, so fail before producing any
        # definition instead.
        if ($seenColId.ContainsKey([int]$piece.ColId)) {
            throw "Object $ObjectId contains more than one ciphertext chunk with colid $($piece.ColId), so it is not safe to decrypt."
        }
        $seenColId[[int]$piece.ColId] = $true

        if ($null -eq $piece.Cipher) {
            throw "Chunk $($piece.ColId) of object $ObjectId has no ciphertext."
        }

        # The definition is UCS-2, so a chunk's ciphertext has to be an even number of bytes. An odd length
        # means a bad in row slice or a bad off row reassembly, and the decode below would silently drop the
        # trailing byte and hand back plausible text, so it is refused here instead.
        if (($piece.Cipher.Length % 2) -ne 0) {
            throw "Chunk $($piece.ColId) of object $ObjectId is $($piece.Cipher.Length) bytes, which is not a whole number of UCS-2 characters."
        }

        $keystreamParams = @{
            FamilyGuid = $FamilyGuid
            ObjectId   = $ObjectId
            ColId      = $piece.ColId
            Length     = $piece.Cipher.Length
        }
        $keystream = Get-EncryptedObjectKeystream @keystreamParams

        $plainText = New-Object byte[] $piece.Cipher.Length
        for ($cipherOffset = 0; $cipherOffset -lt $plainText.Length; $cipherOffset++) {
            $plainText[$cipherOffset] = $piece.Cipher[$cipherOffset] -bxor $keystream[$cipherOffset]
        }

        # The definition is stored as UCS-2, so it is decoded as such rather than with an encoding of choice.
        $null = $scriptBuilder.Append([System.Text.Encoding]::Unicode.GetString($plainText))
    }

    return $scriptBuilder.ToString()
}
