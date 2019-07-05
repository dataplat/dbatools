function Get-DbaUpdateDetail {
    <#
    .SYNOPSIS
        Gets download links and detailed information for KB files (SPs/hotfixes/CUs, etc)

    .DESCRIPTION
        Parses catalog.update.microsoft.com and grabs details for KB files (SPs/hotfixes/CUs, etc)

    .PARAMETER Name
        The KB name or number. For example, KB4057119 or 4057119.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Update
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaUpdateDetail

    .EXAMPLE
        PS C:\> Get-DbaUpdateDetail -Name KB4057119

        Gets information about KB4057119. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Get-DbaUpdateDetail -Name KB4057119, 4057114

        Gets information about KB4057119 and KB4057114. This works for SQL Server or any other KB.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,
        [switch]$EnableException
    )
    process {
        foreach ($kb in $Name) {
            try {
                # Thanks! https://keithga.wordpress.com/2017/05/21/new-tool-get-the-latest-windows-10-cumulative-updates/
                $kb = $kb.Replace("KB", "").Replace("kb", "").Replace("Kb", "")

                $results = Invoke-TlsWebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$kb"
                $kbids = $results.InputFields |
                    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
                    Select-Object -ExpandProperty  ID

                if (-not $kbids) {
                    Write-Message -Level Warning -Message "No results found for $Name"
                    return
                }

                Write-Message -Level Verbose -Message "$kbids"

                $guids = $results.Links |
                    Where-Object ID -match '_link' |
                    Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
                    ForEach-Object { $_.id.replace('_link', '') } |
                    Where-Object { $_ -in $kbids }

                foreach ($guid in $guids) {
                    Write-Message -Level Verbose -Message "Downloading information for $guid"
                    $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
                    $body = @{ updateIDs = "[$post]" }
                    $detailresults = Invoke-TlsWebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body | Select-Object -ExpandProperty Content

                    # sorry, don't know regex. this is ugly af.
                    $title = $detailresults -Split "enTitle ="
                    $title = ($title[1] -Split ';')[0].Replace("'", "")

                    $links = $detailresults | Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" | Select-Object -Unique
                    foreach ($link in $links) {
                        $build = Get-DbaBuildReference -Kb "KB$kb" -WarningAction SilentlyContinue
                        if ($build.NameLevel) {
                            $properties = "Title", "NameLevel", "SPLevel", "KBLevel", "CULevel", "BuildLevel", "SupportedUntil", "Link"
                        } else {
                            $properties = "Title", "Link"
                        }
                        Add-Member -InputObject $build -MemberType NoteProperty -Name Title -Value $title
                        Add-Member -InputObject $build -MemberType NoteProperty -Name Link -Value ($link.matches.value) -PassThru | Select-DefaultView -Property $properties
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}