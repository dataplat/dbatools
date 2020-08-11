function Get-DbaKbUpdate {
    <#
    .SYNOPSIS
        Gets download links and detailed information for KB files (SPs/hotfixes/CUs, etc)

    .DESCRIPTION
        Parses catalog.update.microsoft.com and grabs details for KB files (SPs/hotfixes/CUs, etc)

        Because Microsoft's RSS feed does not work, the command has to parse a few webpages which can result in slowness.

        Use the Simple parameter for simplified output and faster results.

    .PARAMETER Name
        The KB name or number. For example, KB4057119 or 4057119.

    .PARAMETER Simple
        A lil faster. Returns, at the very least: Title, Architecture, Language, Hotfix, UpdateId and Link

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
        https://dbatools.io/Get-DbaKbUpdate

    .EXAMPLE
        PS C:\> Get-DbaKbUpdate -Name KB4057119

        Gets detailed information about KB4057119. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Get-DbaKbUpdate -Name KB4057119, 4057114

        Gets detailed information about KB4057119 and KB4057114. This works for SQL Server or any other KB.

    .EXAMPLE
        PS C:\> Get-DbaKbUpdate -Name KB4057119, 4057114 -Simple

        A lil faster. Returns, at the very least: Title, Architecture, Language, Hotfix, UpdateId and Link
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,
        [switch]$Simple,
        [switch]$EnableException
    )
    begin {
        # Wishing Microsoft offered an RSS feed. Since they don't, we are forced to parse webpages.
        function Get-Info ($Text, $Pattern) {
            $info = $Text -Split $Pattern
            if ($Pattern -match "labelTitle") {
                $part = ($info[1] -Split '</span>')[1]
                $part = $part.Replace("<div>", "")
                ($part -Split '</div>')[0].Trim()
            } elseif ($Pattern -match "span ") {
                ($info[1] -Split '</span>')[0].Trim()
            } else {
                ($info[1] -Split ';')[0].Replace("'", "").Trim()
            }
        }

        function Get-SuperInfo ($Text, $Pattern) {
            $info = $Text -Split $Pattern
            if ($Pattern -match "supersededbyInfo") {
                $part = ($info[1] -Split '<span id="ScopedViewHandler_labelSupersededUpdates_Separator" class="labelTitle">')[0]
            } else {
                $part = ($info[1] -Split '<div id="languageBox" style="display: none">')[0]
            }
            $nomarkup = ($part -replace '<[^>]+>', '').Trim() -split [Environment]::NewLine
            foreach ($line in $nomarkup) {
                $clean = $line.Trim()
                if ($clean) { $clean }
            }
        }

        $baseproperties = "Title",
        "Description",
        "Architecture",
        "NameLevel",
        "SPLevel",
        "KBLevel",
        "CULevel",
        "BuildLevel",
        "SupportedUntil",
        "Language",
        "Classification",
        "SupportedProducts",
        "MSRCNumber",
        "MSRCSeverity",
        "Hotfix",
        "Size",
        "UpdateId",
        "RebootBehavior",
        "RequestsUserInput",
        "ExclusiveInstall",
        "NetworkRequired",
        "UninstallNotes",
        "UninstallSteps",
        "SupersededBy",
        "Supersedes",
        "LastModified",
        "Link"
    }
    process {
        foreach ($kb in $Name) {
            try {
                # Thanks! https://keithga.wordpress.com/2017/05/21/new-tool-get-the-latest-windows-10-cumulative-updates/
                $kb = $kb.Replace("KB", "").Replace("kb", "").Replace("Kb", "")

                $results = Invoke-TlsWebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$kb" -UseBasicParsing -ErrorAction Stop

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
                    $downloaddialog = Invoke-TlsWebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body -UseBasicParsing -ErrorAction Stop | Select-Object -ExpandProperty Content

                    # sorry, don't know regex. this is ugly af.
                    $title = Get-Info -Text $downloaddialog -Pattern 'enTitle ='
                    $arch = Get-Info -Text $downloaddialog -Pattern 'architectures ='
                    $longlang = Get-Info -Text $downloaddialog -Pattern 'longLanguages ='
                    $updateid = Get-Info -Text $downloaddialog -Pattern 'updateID ='
                    $isHotfix = Get-Info -Text $downloaddialog -Pattern 'isHotFix ='

                    if ($arch -eq "AMD64") {
                        $arch = "x64"
                    }
                    if ($title -match '64-Bit' -and $title -notmatch '32-Bit' -and -not $arch) {
                        $arch = "x64"
                    }
                    if ($title -notmatch '64-Bit' -and $title -match '32-Bit' -and -not $arch) {
                        $arch = "x86"
                    }

                    if (-not $Simple) {
                        $detaildialog = Invoke-TlsWebRequest -Uri "https://www.catalog.update.microsoft.com/ScopedViewInline.aspx?updateid=$updateid" -UseBasicParsing -ErrorAction Stop
                        $description = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_desc">'
                        $lastmodified = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_date">'
                        $size = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_size">'
                        $classification = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_labelClassification_Separator" class="labelTitle">'
                        $supportedproducts = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_labelSupportedProducts_Separator" class="labelTitle">'
                        $msrcnumber = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_labelSecurityBulliten_Separator" class="labelTitle">'
                        $msrcseverity = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_msrcSeverity">'
                        $rebootbehavior = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_rebootBehavior">'
                        $requestuserinput = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_userInput">'
                        $exclusiveinstall = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_installationImpact">'
                        $networkrequired = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_connectivity">'
                        $uninstallnotes = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_labelUninstallNotes_Separator" class="labelTitle">'
                        $uninstallsteps = Get-Info -Text $detaildialog -Pattern '<span id="ScopedViewHandler_labelUninstallSteps_Separator" class="labelTitle">'
                        $supersededby = Get-SuperInfo -Text $detaildialog -Pattern '<div id="supersededbyInfo" TABINDEX="1" >'
                        $supersedes = Get-SuperInfo -Text $detaildialog -Pattern '<div id="supersedesInfo" TABINDEX="1">'

                        $product = $supportedproducts -split ","
                        if ($product.Count -gt 1) {
                            $supportedproducts = @()
                            foreach ($line in $product) {
                                $clean = $line.Trim()
                                if ($clean) { $supportedproducts += $clean }
                            }
                        }
                    }

                    $links = $downloaddialog | Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" | Select-Object -Unique

                    foreach ($link in $links) {
                        $build = Get-DbaBuildReference -Kb "KB$kb" -WarningAction SilentlyContinue
                        $properties = $baseproperties

                        if (-not $build.NameLevel) {
                            $properties = $properties | Where-Object { $PSItem -notin "NameLevel", "SPLevel", "KBLevel", "CULevel", "BuildLevel", "SupportedUntil" }
                        }

                        if ($Simple) {
                            $properties = $properties | Where-Object { $PSItem -notin "LastModified", "Description", "Size", "Classification", "SupportedProducts", "MSRCNumber", "MSRCSeverity", "RebootBehavior", "RequestsUserInput", "ExclusiveInstall", "NetworkRequired", "UninstallNotes", "UninstallSteps", "SupersededBy", "Supersedes" }
                        }

                        [pscustomobject]@{
                            Title             = $title
                            NameLevel         = $build.NameLevel
                            SPLevel           = $build.SPLevel
                            KBLevel           = $build.KBLevel
                            CULevel           = $build.CULevel
                            BuildLevel        = $build.BuildLevel
                            SupportedUntil    = $build.SupportedUntil
                            Architecture      = $arch
                            Language          = $longlang
                            Hotfix            = $isHotfix
                            Description       = $description
                            LastModified      = $lastmodified
                            Size              = $size
                            Classification    = $classification
                            SupportedProducts = $supportedproducts
                            MSRCNumber        = $msrcnumber
                            MSRCSeverity      = $msrcseverity
                            RebootBehavior    = $rebootbehavior
                            RequestsUserInput = $requestuserinput
                            ExclusiveInstall  = $exclusiveinstall
                            NetworkRequired   = $networkrequired
                            UninstallNotes    = $uninstallnotes
                            UninstallSteps    = $uninstallsteps
                            UpdateId          = $updateid
                            Supersedes        = $supersedes
                            SupersededBy      = $supersededby
                            Link              = $link.matches.value
                        } | Select-DefaultView -Property $properties
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}