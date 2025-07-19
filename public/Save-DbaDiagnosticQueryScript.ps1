function Save-DbaDiagnosticQueryScript {
    <#
    .SYNOPSIS
        Save-DbaDiagnosticQueryScript downloads the most recent version of all Glenn Berry DMV scripts

    .DESCRIPTION
        The dbatools module will have the diagnostic queries pre-installed. Use this only to update to a more recent version or specific versions.

        This function is mainly used by Invoke-DbaDiagnosticQuery, but can also be used independently to download the Glenn Berry DMV scripts.

        Use this function to pre-download the scripts from a device with an Internet connection.

        The function Invoke-DbaDiagnosticQuery will try to download these scripts automatically, but it obviously needs an internet connection to do that.

    .PARAMETER Path
        Specifies the path to the output

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, GlennBerry
        Author: Andre Kamman (@AndreKamman), andrekamman.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Save-DbaDiagnosticQueryScript

    .EXAMPLE
        PS C:\> Save-DbaDiagnosticQueryScript -Path c:\temp

        Downloads the most recent version of all Glenn Berry DMV scripts to the specified location.
        If Path is not specified, the "My Documents" location will be used.
    #>
    [CmdletBinding()]
    param (
        [System.IO.FileInfo]$Path = [Environment]::GetFolderPath("mydocuments"),
        [switch]$EnableException
    )
    function Get-WebData {
        param ($uri)
        try {
            try {
                $data = (Invoke-TlsWebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop)
            } catch {
                (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                $data = (Invoke-TlsWebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop)
            }
            return $data
        } catch {
            Stop-Function -Message "Invoke-TlsWebRequest failed: $_" -Target $data -ErrorRecord $_
            return
        }
    }

    if (-not (Test-Path $Path)) {
        Stop-Function -Message "Path does not exist or access denied" -Target $path
        return
    }

    Add-Type -AssemblyName System.Web

    $glennberryResources = "https://glennsqlperformance.com/resources/"
    $DropboxLinkFilter = "*dropbox.com*"
    $LinkTitleFilter = "*Diagnostic Information Queries*"
    $ExcludeSpreadsheet = "*Results Spreadsheet*"
    $FileTypeFilter = "*.sql*"

    Write-Message -Level Verbose -Message "Downloading Glenn Berry Resources Page"
    $page = Get-WebData -uri $glennberryResources

    $glenberrysql += ($page.Links | Where-Object { $_.href -like $DropboxLinkFilter -and $_.outerHTML -like $LinkTitleFilter -and $_.outerHTML -notlike $ExcludeSpreadsheet -and $_.outerHTML -like $FileTypeFilter } | ForEach-Object {
            [PSCustomObject]@{
                URL        = $_.href
                SQLVersion = $_.outerHTML -replace "<.+`">", "" -replace "</a>", "" -replace " Diagnostic Information Queries", "" -replace "SQL Server ", "" -replace ' ', ''
            }
        })

    Write-Message -Level Verbose -Message "Found $($glenberrysql.Count) documents to download"
    foreach ($doc in $glenberrysql) {
        try {
            $link = $doc.URL.ToString().Replace('dl=0', 'dl=1')
            Write-Message -Level Verbose -Message "Downloading $link)"
            Write-ProgressHelper -Activity "Downloading Glenn Berry's most recent DMVs" -ExcludePercent -Message "Downloading $link" -StepNumber 1
            $filename = Join-Path -Path $Path  -ChildPath "SQLServerDiagnosticQueries_$($doc.SQLVersion).sql"
            Invoke-TlsWebRequest -Uri $link -OutFile $filename -ErrorAction Stop
            Get-ChildItem -Path $filename
        } catch {
            Stop-Function -Message "Requesting and writing file failed: $_" -Target $filename -ErrorRecord $_
            return
        }
    }
}