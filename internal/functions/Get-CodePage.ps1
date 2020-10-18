function Get-CodePage {
    <#
        .SYNOPSIS
            Converts Microsoft's code page ID to human readable format

        .DESCRIPTION
            Converts Microsoft's code page ID to human readable format

        .PARAMETER Id
            The code page ID

        .EXAMPLE
            Get-CodePage 1252

            Returns a pscustomobject with id, alias and name
    #>
    [CmdletBinding()]
    param (
        [int]$id
    )
    process {
        $encoding = [System.Text.Encoding]::GetEncoding($id)
        $IncludeProps = 'CodePage', 'BodyName', 'EncodingName', 'HeaderName', 'WebName', 'IsSingleByte'
        Select-DefaultView -InputObject $encoding -Property $IncludeProps
    }
}