function Get-KBLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    # Thanks! https://keithga.wordpress.com/2017/05/21/new-tool-get-the-latest-windows-10-cumulative-updates/
    $kb = $Name.Replace("KB", "")
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
        $links = Invoke-TlsWebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body |
            Select-Object -ExpandProperty Content |
            Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" |
            Select-Object -Unique

        foreach ($link in $links) {
            $build = Get-DbaBuildReference -Kb "KB$kb"
            Add-Member -InputObject $build -MemberType NoteProperty -Name Link -Value ($link.matches.value) -PassThru | Select-Object NameLevel, SPLevel, KBLevel, CULevel, BuildLevel, SupportedUntil, Link
        }
    }
}