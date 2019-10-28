function Convert-DbaLSN {
    <#
    .SYNOPSIS
        Converts Lsns betweent Hex and/or numeric formats

    .DESCRIPTION
        Function takes an LSN in either split Hexadecimal format () or numberic

        It then returns both formats in an object

    .PARAMETER LSN
        The LSN value to be converted

    .EXAMPLE
        PS C:\ $output = Convert-DbaLSN -LSN 0000002f:000044aa:002b

        Will return object $Output with the following value
        $Output.HexLSN = 0000002f:000044aa:002b
        $Output.NumbericLSN =
    #>
    [CmdletBinding()]
    param(
        [string]$LSN,
        [switch]$EnableException
    )

    if ($LSN -match '^[a-fA-F0-9]{8}:[a-fA-F0-9]{8}:[a-fA-F0-9]{4}$') {
        Write-Message -Message 'Hexadecimal LSN passed in, converting to numeric' -Level Verbose
        $sections = $LSN.Split(':')
        $sect1 = [System.Convert]::ToInt64($sections[0], 16).ToString()
        $sect2 = [System.Convert]::ToInt64($sections[1], 16).ToString().PadLeft(10, '0')
        $sect3 = [System.Convert]::ToInt64($sections[2], 16).ToString().PadLeft(5, '0')
        $Hexadecimal = $LSN
        $Numeric = $sect1 + $sect2 + $sect3

    } elseif ($LSN -match '^[0-9]{15}[0-9]+$') {
        Write-Message -Message 'Numeric LSN passed in, converting to Hexadecimal' -Level Verbose
        $sect1 = '{0:x}' -f [System.Convert]::ToString($LSN.Substring(0, $LSN.length - 15), 16).PadLeft(8, '0')
        $sect2 = '{0:x}' -f [System.Convert]::ToString($LSN.Substring($lsn.length - 14, 9), 16).PadLeft(8, '0')
        $sect3 = '{0:x}' -f [System.Convert]::ToString($LSN.Substring($lsn.length - 5, 5), 16).PadLeft(4, '0')
        $Numeric = $LSN
        $Hexadecimal = $sect1 + ':' + $sect2 + ':' + $sect3
    } else {
        Stop-Function -Message 'LSN passed in is neither Numeric nor in the correct hexadecimal format'
        return
    }

    [PSCustomObject]@{
        Hexadecimal = $Hexadecimal
        Numeric     = $Numeric
    }
}