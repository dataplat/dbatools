function Get-DbaLatestSQLVersion {
    <#
        .SYNOPSIS
            Get latest version of SQL Server SP & CU
        .DESCRIPTION
            Function to get the latest version of SQL server. Source from online dbatools Github community
        .PARAMETER ServerMajorVersion
            [OPTIONAL] When provided the output result will only contain latest version for that SQL Server
        .PARAMETER WebVersionUrl
            [OPTIONAL] Override the default URL for fetching all SQL Server Versions. Default points to dbatools repository.
        .PARAMETER OfflineOnly
            [OPTIONAL] When enabled, the function will use the local version of the reference data that's bundled with dbatools module. Using this parameter might result in outdated dataset. Use only when no internet connection is available.
        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        .EXAMPLE
            Get-LatestSQLVersion
            Get-LatestSQLVersion -OfflineOnly
            Get-LatestSQLVersion -ServerMajorVersion "10.50"

        .NOTES
        Tags: Version
        Author: Vidhya Sagar (@sqlarticles)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaLatestSQLVersion
    #>
    param(
        [ValidateSet("8", "9", "10", "10.50", "11", "12", "13", "14", "15", "16")]
        [parameter(Mandatory = $false)]
        [string]$ServerMajorVersion,
        [parameter(Mandatory = $false)]
        [Uri]$WebVersionUrl = "https://raw.githubusercontent.com/dataplat/dbatools/development/bin/dbatools-buildref-index.json",
        [switch]$OfflineOnly = $false,
        [switch]$EnableException = $false
    )

    begin {

        $moduleReferenceFile = Join-DbaPath -Path $PSScriptRoot -Child ..\bin\dbatools-buildref-index.json

        $latestVersion = New-Object System.Collections.Generic.List[Object]

        $sqlMajorVersions = @("8", "9", "10.0", "10.50", "11", "12", "13", "14", "15", "16")

        if ($OfflineOnly -eq $false) {
            try {
                $allSqlVersion = (Invoke-WebRequest -Uri $WebVersionUrl).Content | ConvertFrom-Json
            } catch {
                Write-Message -Level Warning -Message "Unable to read from online reference file [$WebVersionUrl]. Using local reference file (might not have the latest releases)"
            }
        }

        if (-not($allSqlVersion) ) {
            try {
                $allSqlVersion = Get-Content -Path $moduleReferenceFile | ConvertFrom-Json
            } catch {
                Stop-Function -Message "Unable to read the reference file online and also locally." -ErrorRecord $_ -Target $moduleReferenceFile -EnableException $EnableException
            }
        }

    }
    process {
        if ($null -ne $allSqlVersion) {
            foreach ($version in $sqlMajorVersions) {
                $wildVersion = "$version*"
                $lastestSP = $allSqlVersion.Data | Select-Object Version, CU, SP, KBList | Where-Object { $_.Version -like $wildVersion -and $null -ne $_.SP } | Sort-Object -Bottom 1
                $latestPatch = $allSqlVersion.Data | Select-Object Version, CU, SP, KBList | Where-Object { $_.Version -like $wildVersion -and $null -eq $_.SP } | Sort-Object -Bottom 1
                $latestVersionObject = [PSCustomObject]@{
                    SQLName            = switch ($version) {
                        "8" { "SQL 2000" }
                        "9" { "SQL 2005" }
                        "10.0" { "SQL 2008" }
                        "10.50" { "SQL 2008 R2" }
                        "11" { "SQL 2012" }
                        "12" { "SQL 2014" }
                        "13" { "SQL 2016" }
                        "14" { "SQL 2017" }
                        "15" { "SQL 2019" }
                        "16" { "SQL 2022" }
                    }
                    SQLMajorVersion    = if ($version -eq "10.0") { "10" } else { $version }
                    LatestSP           = $lastestSP.SP
                    LatestSPVersion    = $lastestSP.Version
                    LatestSPKB         = $lastestSP.KBList
                    LatestPatch        = $latestPatch.CU
                    LatestPatchVersion = $latestPatch.Version
                    LatestPatchKB      = $latestPatch.KBList
                }
                $latestVersion.Add($latestVersionObject)
            }
        }
    }
    end {
        if ($ServerMajorVersion) {
            $latestVersion = $latestVersion | Where-Object { $_.SQLMajorVersion -eq $ServerMajorVersion }
        }
        return $latestVersion
    }
}