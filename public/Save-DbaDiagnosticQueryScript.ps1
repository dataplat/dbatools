function Save-DbaDiagnosticQueryScript {
    <#
    .SYNOPSIS
        Downloads Glenn Berry's SQL Server Diagnostic Information Queries for performance monitoring and troubleshooting

    .DESCRIPTION
        Downloads the latest versions of Glenn Berry's renowned SQL Server Diagnostic Information Queries from his website. These DMV-based scripts are essential tools for DBAs to assess SQL Server health, identify performance bottlenecks, and gather comprehensive system information across all SQL Server versions including Azure SQL Database and Managed Instance.

        The dbatools module includes diagnostic queries pre-installed, but this function lets you update to more recent versions or download specific versions for your environment. This is particularly valuable since Glenn Berry regularly updates these scripts with new insights and compatibility improvements.

        This function is primarily used by Invoke-DbaDiagnosticQuery, but can also be used independently to download the scripts. Use this to pre-download scripts from a device with internet connection for later use on systems without internet access.

        The function automatically detects and downloads scripts for all available SQL Server versions found on Glenn Berry's resources page, saving them with version-specific filenames for easy identification.

    .PARAMETER Path
        Specifies the directory path where Glenn Berry's diagnostic query scripts will be downloaded. Defaults to the current user's Documents folder.
        Use this when you need to organize scripts in a specific location, such as a shared network drive for team access or a local folder structure for different environments.

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

    .OUTPUTS
        System.IO.FileInfo

        Returns one file information object for each diagnostic script downloaded. Each object represents a downloaded SQL script file containing Glenn Berry's diagnostic queries.

        Properties:
        - FullName: Full file path of the downloaded diagnostic query script (e.g., C:\Users\UserName\Documents\SQLServerDiagnosticQueries_2022.sql)
        - Name: The filename of the script (e.g., SQLServerDiagnosticQueries_2022.sql)
        - Extension: File extension (.sql)
        - Length: File size in bytes
        - CreationTime: DateTime when the file was created
        - LastWriteTime: DateTime when the file was last modified
        - Directory: The directory object containing the file
        - Attributes: File attributes (Archive, etc.)

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

    if (-not (Test-Path $Path)) {
        Stop-Function -Message "Path does not exist or access denied" -Target $path
        return
    }

    Add-Type -AssemblyName System.Web

    $glennberryResources = "https://glennsqlperformance.com/resources/"

    # The links of the resources page, used when the page cannot be read or lists no scripts
    $knownScriptUrls = @(
        "https://www.dropbox.com/scl/fi/8qtdi3w5ix2bra8ytk7oy/SQL-Server-2025-Diagnostic-Information-Queries.sql?rlkey=kv1t4fdwe60nkd7fl0jukhnnq&dl=1",
        "https://www.dropbox.com/s/6rb2f97ocvkq7fw/SQL%20Server%202022%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/k1vauzxxhyh1fnb/SQL%20Server%202019%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/scl/fi/0q4sbb7xb3x3vmbhkdga3/SQL-Server-2017-Diagnostic-Information-Queries.sql?rlkey=nli5q22tgqqw7oxvoqyeujmmc&dl=1",
        "https://www.dropbox.com/s/pkpxihdkq3odgbj/SQL%20Server%202016%20SP2%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/w6gi8j76k64fgbg/SQL%20Server%202016%20SP1%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/uttp0843e5078vs/SQL%20Server%202014%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/3l4yotzedk45xeh/SQL%20Server%202012%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/fq6hyw899fe3crv/SQL%20Server%202008%20R2%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/mjxw1w9tgw7eo6g/SQL%20Server%202008%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/3kkskuheyzauih9/SQL%20Server%202005%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/8y2fdgxfbjyiid8/Azure%20SQL%20Database%20Diagnostic%20Information%20Queries.sql?dl=1",
        "https://www.dropbox.com/s/xwi4jzns4rcvnnk/SQL%20Managed%20Instance%20Diagnostic%20Information%20Queries.sql?dl=1"
    )

    Write-Message -Level Verbose -Message "Downloading Glenn Berry Resources Page"

    # The bot filter in front of the site can answer with a 403 challenge page (it does for PowerShell 7 on Windows),
    # so a page that cannot be read falls back to the known links instead of failing the command
    $pageContent = $null
    try {
        try {
            $pageContent = (Invoke-TlsWebRequest -Uri $glennberryResources -UseBasicParsing -ErrorAction Stop)
        } catch {
            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $pageContent = (Invoke-TlsWebRequest -Uri $glennberryResources -UseBasicParsing -ErrorAction Stop)
        }
    } catch {
        Write-Message -Level Verbose -Message "Reading Glenn Berry's resources page failed, using the script links known to dbatools: $($_.Exception.Message)"
    }

    $resourcesContent = ""
    if ($pageContent.Content) {
        $resourcesContent = $pageContent.Content
    }

    # Simplified approach: find ALL Dropbox .sql URLs and extract version from URL itself
    $allDropboxUrls = @()

    # Pattern to find any Dropbox SQL URL (both old and new formats)
    $urlPattern = '(https://www\.dropbox\.com/(?:s/[\w]+|scl/fi/[\w]+)/[^"\s]*\.sql[^"\s]*dl=0)'
    $urlMatches = [regex]::Matches($resourcesContent, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

    foreach ($match in $urlMatches) {
        $url = $match.Groups[1].Value
        $downloadUrl = $url -replace 'dl=0', 'dl=1'

        # Extract SQL version from the URL filename - IMPROVED VERSION
        $sqlVersion = "Unknown"

        # Check for new URL format first (e.g., SQL-Server-2025-Diagnostic)
        if ($url -match 'SQL-Server-(\d{4})(?:-(SP\d|R2))?-Diagnostic') {
            $sqlVersion = $matches[1]
            if ($matches[2]) {
                $sqlVersion += $matches[2] -replace '-', ''
            }
        }
        # Check for URL-encoded format (e.g., SQL%20Server%202016%20SP2%20Diagnostic)
        elseif ($url -match 'SQL%20Server%20(\d{4})(?:%20(SP\d|R2))?%20Diagnostic') {
            $sqlVersion = $matches[1]
            if ($matches[2]) {
                $sqlVersion += $matches[2]
            }
        }
        # Check for space format in URL (e.g., SQL Server 2008 R2 Diagnostic)
        elseif ($url -match 'SQL.*Server.*(\d{4})(?:\s+(SP\d|R2))?\s+Diagnostic') {
            $sqlVersion = $matches[1]
            if ($matches[2]) {
                $sqlVersion += $matches[2] -replace '\s', ''
            }
        }
        # Check for Azure SQL Database
        elseif ($url -match 'Azure.*SQL.*Database.*Diagnostic') {
            $sqlVersion = 'AzureDatabase'
        }
        # Check for SQL Managed Instance
        elseif ($url -match 'SQL.*Managed.*Instance.*Diagnostic') {
            $sqlVersion = 'AzureManagedInstance'
        }
        # Fallback: try to extract from filename directly
        else {
            # Extract filename from URL
            $decodedUrl = [System.Web.HttpUtility]::UrlDecode($url)
            if ($decodedUrl -match '(\d{4})\s*(SP\d|R2)?') {
                $sqlVersion = $matches[1]
                if ($matches[2]) {
                    $sqlVersion += $matches[2] -replace '\s', ''
                }
            }
        }

        $allDropboxUrls += $downloadUrl
    }

    if ($allDropboxUrls.Count -eq 0) {
        Write-Message -Level Verbose -Message "Found no script links on Glenn Berry's resources page, using the script links known to dbatools"
        $allDropboxUrls = $knownScriptUrls
    }

    # Remove duplicates
    $allDropboxUrls = $allDropboxUrls | Select-Object -Unique

    $glenberrysql = @()
    foreach ($url in $allDropboxUrls) {
        # Extract version info from URL - IMPROVED VERSION
        $sqlVersion = "Unknown"
        $linkText = ""

        # Decode URL for better pattern matching
        $decodedUrl = [System.Web.HttpUtility]::UrlDecode($url)

        # Check for new URL format first (e.g., SQL-Server-2025-Diagnostic)
        if ($url -match 'SQL-Server-(\d{4})(?:-(SP\d|R2))?-Diagnostic') {
            $sqlVersion = $matches[1]
            if ($matches[2]) {
                $sqlVersion += $matches[2] -replace '-', ''
            }
            $linkText = "SQL Server $sqlVersion Diagnostic Information Queries"
        }
        # Check for URL-encoded format (e.g., SQL%20Server%202016%20SP2%20Diagnostic)
        elseif ($url -match 'SQL%20Server%20(\d{4})(?:%20(SP\d|R2))?%20Diagnostic') {
            $sqlVersion = $matches[1]
            if ($matches[2]) {
                $sqlVersion += $matches[2]
            }
            $linkText = "SQL Server $sqlVersion Diagnostic Information Queries"
        }
        # Check decoded URL for better matching
        elseif ($decodedUrl -match 'SQL Server (\d{4})\s+(SP\d|R2)\s+Diagnostic') {
            $sqlVersion = $matches[1] + $matches[2]
            $linkText = "SQL Server $sqlVersion Diagnostic Information Queries"
        } elseif ($decodedUrl -match 'SQL Server (\d{4})\s+Diagnostic') {
            $sqlVersion = $matches[1]
            $linkText = "SQL Server $sqlVersion Diagnostic Information Queries"
        }
        # Check for Azure SQL Database
        elseif ($url -match 'Azure.*SQL.*Database.*Diagnostic') {
            $sqlVersion = 'AzureDatabase'
            $linkText = "Azure SQL Database Diagnostic Information Queries"
        }
        # Check for SQL Managed Instance
        elseif ($url -match 'SQL.*Managed.*Instance.*Diagnostic') {
            $sqlVersion = 'AzureManagedInstance'
            $linkText = "SQL Managed Instance Diagnostic Information Queries"
        }

        $glenberrysql += [PSCustomObject]@{
            URL        = $url
            SQLVersion = $sqlVersion
            LinkText   = $linkText
        }
    }

    if ($glenberrysql.Count -eq 0) {
        Stop-Function -Message "No diagnostic query links found on Glenn Berry's resources page. The website structure may have changed."
        return
    }

    Write-Message -Level Verbose -Message "Found $($glenberrysql.Count) documents to download"

    try {
        foreach ($doc in $glenberrysql) {
            try {
                $link = $doc.URL.ToString()
                # Extra safety: clean HTML entities one more time before download
                $link = $link -replace '&amp;', '&'
                Write-Message -Level Verbose -Message "Downloading $link"
                Write-ProgressHelper -Activity "Downloading Glenn Berry's most recent DMVs" -ExcludePercent -Message "Downloading $link" -StepNumber 1
                $filename = Join-Path -Path $Path -ChildPath "SQLServerDiagnosticQueries_$($doc.SQLVersion).sql"
                Invoke-TlsWebRequest -Uri $link -OutFile $filename -ErrorAction Stop
                Get-ChildItem -Path $filename
            } catch {
                Stop-Function -Message "Requesting and writing file failed: $_" -Target $filename -ErrorRecord $_
                return
            }
        }
    } finally {
        Write-ProgressHelper -Completed
    }
}