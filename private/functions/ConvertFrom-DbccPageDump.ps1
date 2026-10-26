function ConvertFrom-DbccPageDump {
    <#
    .SYNOPSIS
        Internal function.

    .DESCRIPTION
        Turns the hex memory dump that DBCC PAGE prints for one page into the raw bytes of that page.

        A dump line looks like this, an address, a colon, groups of eight hex digits, then an ASCII gutter
        that renders the same bytes as characters:

            0000000332FF4000:   01010400 00820100 78da1801 01001100 5d8e0600  .......x....]..

        Two properties of that format make the obvious parser wrong, and both fail silently:

        - The line width is not fixed. The same build of SQL Server emits 16 bytes per line for some pages
          and 20 for others.
        - The gutter can begin with a token of exactly eight hex digits, because a module definition easily
          contains an eight character run of hex digits. The rule "a token of exactly eight hex digits is
          data" then takes that gutter as one more group of four bytes, and a line contributes 24 bytes
          instead of 20.

        Appending the bytes in order would shift everything after such a line by four, which leaves the
        slot array at the end of the page decoding to rubbish while the result is still exactly 8192 bytes
        and nothing throws. So each line's bytes are placed at the offset its own address gives. A stray
        gutter token then lands where the next line's bytes go and is overwritten by them, and nothing else
        moves, which also makes the line width irrelevant.

        Coverage is tracked and every byte of the page is required, because a line that went missing would
        otherwise leave a hole of zeroes that nothing else would reveal.

        The address is a memory address rather than an offset into the page and does not start at zero, so
        the first line that is accepted is what defines where the page begins.

        This is a function of its own, rather than part of the reader that calls it, so that it can be unit
        tested without a SQL Server instance. Both of the properties above are reproducible from synthetic
        dump text, and nothing else in the suite would catch a regression in them.

        This function is used by the following private functions:
        - Get-EncryptedObjectImageValue

    .PARAMETER DumpLine
        The lines of the memory dump section of one page, in the order DBCC PAGE returned them.

    .PARAMETER PageSize
        The size of a page in bytes. Defaults to 8192.

    .NOTES
        Tags: Page, DBCC
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        ConvertFrom-DbccPageDump -DumpLine $dumpLine

        Returns the 8192 bytes that the dump describes.
    #>
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$DumpLine,
        [int]$PageSize = 8192
    )

    $image = New-Object byte[] $PageSize
    $covered = New-Object bool[] $PageSize
    $coveredCount = 0
    $baseAddress = $null

    foreach ($line in $DumpLine) {
        if ($null -eq $line) {
            continue
        }

        $colonPosition = $line.IndexOf(":")
        if ($colonPosition -le 0) {
            continue
        }

        $address = $line.Substring(0, $colonPosition).Trim()
        if ($address.Length -lt 8 -or $address.Length -gt 16 -or $address -notmatch "^[0-9A-Fa-f]+$") {
            continue
        }

        $addressValue = [Convert]::ToUInt64($address, 16)
        if ($null -eq $baseAddress) {
            $baseAddress = $addressValue
        }
        if ($addressValue -lt $baseAddress) {
            continue
        }

        $imageOffset = [int]($addressValue - $baseAddress)
        if ($imageOffset -ge $PageSize) {
            continue
        }

        foreach ($token in ($line.Substring($colonPosition + 1).Trim() -split "\s+")) {
            # The first token that is not exactly eight hex digits is the ASCII gutter.
            if ($token -notmatch "^[0-9A-Fa-f]{8}$") {
                break
            }
            if (($imageOffset + 4) -gt $PageSize) {
                break
            }

            # One parse per group of four bytes rather than one per byte. The group prints its bytes in
            # order, so the most significant byte of the parsed value is the first.
            $word = [Convert]::ToUInt32($token, 16)
            for ($shift = 24; $shift -ge 0; $shift -= 8) {
                $image[$imageOffset] = [byte](($word -shr $shift) -band 0xFF)
                if (-not $covered[$imageOffset]) {
                    $covered[$imageOffset] = $true
                    $coveredCount++
                }
                $imageOffset++
            }
        }
    }

    if ($coveredCount -lt $PageSize) {
        throw "Incomplete page dump. Only $coveredCount of $PageSize bytes were accounted for."
    }

    # -NoEnumerate keeps PowerShell from unrolling the byte array into the pipeline, so the caller
    # receives one byte[] rather than 8192 separate bytes and can still bind it to [Array]::Copy.
    Write-Output -NoEnumerate $image
}
