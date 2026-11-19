#nullable enable

using System;
using System.Collections;
using System.IO;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Downloads Glenn Berry diagnostic-query scripts. Port of
/// public/Save-DbaDiagnosticQueryScript.ps1 (W1-118). The full function body rides one
/// module-scoped PowerShell hop so path truthiness, the two-attempt web request, dynamic
/// Stop-Function behavior, regex/$matches state, URL decoding and deduplication, version
/// naming fallbacks, verbose/progress streams, download/write failures, and FileInfo output
/// retain the source engine's observable behavior. Surface pinned by
/// migration/baselines/Save-DbaDiagnosticQueryScript.json.
/// </summary>
[Cmdlet(VerbsData.Save, "DbaDiagnosticQueryScript")]
public sealed class SaveDbaDiagnosticQueryScriptCommand : DbaBaseCmdlet
{
    /// <summary>The directory where diagnostic query scripts are written.</summary>
    [Parameter(Position = 0)]
    public FileInfo? Path { get; set; } = BuildDefaultPath();

    private static FileInfo? BuildDefaultPath()
    {
        string path = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        return string.IsNullOrEmpty(path) ? null : new FileInfo(path);
    }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted) { return; }
        // The source's typed default ([System.IO.FileInfo]$Path = [Environment]::GetFolderPath(...))
        // FAULTS the invocation when the folder resolves empty AND -Path was not supplied - PS only
        // evaluates the default for unbound parameters, so a bound -Path must never trip this.
        // Riding the engine's own converter on "" reproduces the cast fault organically before any
        // body work (empty-MyDocuments cannot be staged on the lab, so the exact outer record shape
        // is a documented degradation).
        if (Path is null && !TestBound("Path"))
            LanguagePrimitives.ConvertTo(string.Empty, typeof(FileInfo),
                System.Globalization.CultureInfo.InvariantCulture);
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            Path, EnableException.ToBool(), BoundVerbose(), BoundDebug());
    }

    private object? BoundDebug()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out object? debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    private object? BoundVerbose()
    {
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out object? verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    private const string BodyScript = """
param($Path, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($Path, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not (Test-Path $Path)) {
        Stop-Function -Message "Path does not exist or access denied" -Target $path -FunctionName Save-DbaDiagnosticQueryScript
        return
    }

    Add-Type -AssemblyName System.Web

    $glennberryResources = "https://glennsqlperformance.com/resources/"

    Write-Message -Level Verbose -Message "Downloading Glenn Berry Resources Page" -FunctionName Save-DbaDiagnosticQueryScript -ModuleName "dbatools"

    try {
        try {
            $pageContent = (Invoke-TlsWebRequest -Uri $glennberryResources -UseBasicParsing -ErrorAction Stop)
        } catch {
            (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            $pageContent = (Invoke-TlsWebRequest -Uri $glennberryResources -UseBasicParsing -ErrorAction Stop)
        }
    } catch {
        Stop-Function -Message "Invoke-TlsWebRequest failed: $_" -Target $pageContent -ErrorRecord $_ -FunctionName Save-DbaDiagnosticQueryScript
        return
    }

    if (-not $pageContent.Content) {
        Stop-Function -Message "Retrieved empty content from Glenn Berry's resources page" -FunctionName Save-DbaDiagnosticQueryScript
        return
    }

    # Simplified approach: find ALL Dropbox .sql URLs and extract version from URL itself
    $allDropboxUrls = @()

    # Pattern to find any Dropbox SQL URL (both old and new formats)
    $urlPattern = '(https://www\.dropbox\.com/(?:s/[\w]+|scl/fi/[\w]+)/[^"\s]*\.sql[^"\s]*dl=0)'
    $urlMatches = [regex]::Matches($pageContent.Content, $urlPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

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
        Stop-Function -Message "No diagnostic query links found on Glenn Berry's resources page. The website structure may have changed." -FunctionName Save-DbaDiagnosticQueryScript
        return
    }

    Write-Message -Level Verbose -Message "Found $($glenberrysql.Count) documents to download" -FunctionName Save-DbaDiagnosticQueryScript -ModuleName "dbatools"

    foreach ($doc in $glenberrysql) {
        try {
            $link = $doc.URL.ToString()
            # Extra safety: clean HTML entities one more time before download
            $link = $link -replace '&amp;', '&'
            Write-Message -Level Verbose -Message "Downloading $link" -FunctionName Save-DbaDiagnosticQueryScript -ModuleName "dbatools"
            Write-ProgressHelper -Activity "Downloading Glenn Berry's most recent DMVs" -ExcludePercent -Message "Downloading $link" -StepNumber 1
            $filename = Join-Path -Path $Path -ChildPath "SQLServerDiagnosticQueries_$($doc.SQLVersion).sql"
            Invoke-TlsWebRequest -Uri $link -OutFile $filename -ErrorAction Stop
            Get-ChildItem -Path $filename
        } catch {
            Stop-Function -Message "Requesting and writing file failed: $_" -Target $filename -ErrorRecord $_ -FunctionName Save-DbaDiagnosticQueryScript
            return
        }
    }
} $Path $EnableException $__boundVerbose $__boundDebug 3>&1 2>&1
""";
}
