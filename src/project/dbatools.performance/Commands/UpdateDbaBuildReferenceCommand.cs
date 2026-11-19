#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Refreshes the local SQL build-reference index. Port of
/// public/Update-DbaBuildReference.ps1 (W1-135). The complete body rides an advanced
/// module-scoped PowerShell hop so private configuration/web/message helpers, filesystem
/// behavior, test mocks, error handling, and stream preferences retain the function's
/// engine semantics. Surface pinned by migration/baselines/Update-DbaBuildReference.json.
/// </summary>
[Cmdlet(VerbsData.Update, "DbaBuildReference", DefaultParameterSetName = "Build")]
public sealed class UpdateDbaBuildReferenceCommand : DbaBaseCmdlet
{
    /// <summary>Local JSON build-reference file to use instead of downloading.</summary>
    [Parameter(Position = 0)]
    public string? LocalFile { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            LocalFile, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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
        }
    }

    private const string ProcessScript = """
param($LocalFile, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($LocalFile, $EnableException)

        function Get-DbaBuildReferenceIndexOnline {
            [CmdletBinding()]
            param (
                [bool]
                $EnableException
            )
            $url = Get-DbatoolsConfigValue -Name 'assets.sqlbuildreference'
            try {
                $webContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
            } catch {
                try {
                    Write-Message -Level Verbose -Message "Probably using a proxy for internet access, trying default proxy settings"
                    (New-Object System.Net.WebClient).Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
                    $webContent = Invoke-TlsWebRequest $url -UseBasicParsing -ErrorAction Stop
                } catch {
                    Write-Message -Level Warning -Message "Couldn't download updated index from $url"
                    return
                }
            }
            return $webContent.Content
        }

        $Moduledirectory = $script:PSModuleRoot
        $orig_idxfile = Resolve-Path "$Moduledirectory\bin\dbatools-buildref-index.json"
        $DbatoolsData = Get-DbatoolsConfigValue -Name 'Path.DbatoolsData'
        $writable_idxfile = Join-Path $DbatoolsData "dbatools-buildref-index.json"

        if (-not (Test-Path $orig_idxfile)) {
            Write-Message -Level Warning -Message "Unable to read local SQL build reference file. Please check your module integrity or reinstall dbatools." -FunctionName Update-DbaBuildReference -ModuleName "dbatools"
        }

        if ((-not (Test-Path $orig_idxfile)) -and (-not (Test-Path $writable_idxfile))) {
            throw "Build reference file not found, please check module health."
        }

        # If no writable copy exists, create one and return the module original
        if (-not (Test-Path $writable_idxfile)) {
            Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
            $offline_time = Get-Date (Get-Content $orig_idxfile -Raw | ConvertFrom-Json).LastUpdated
        }

        # Else, if both exist, update the writeable if necessary and return the current version
        elseif (Test-Path $orig_idxfile) {
            $module_content = Get-Content $orig_idxfile -Raw | ConvertFrom-Json
            $data_content = Get-Content $writable_idxfile -Raw | ConvertFrom-Json

            $module_time = Get-Date $module_content.LastUpdated
            $data_time = Get-Date $data_content.LastUpdated

            $offline_time = $module_time
            if ($module_time -gt $data_time) {
                Copy-Item -Path $orig_idxfile -Destination $writable_idxfile -Force -ErrorAction Stop
            } else {
                $offline_time = $data_time
            }
        }

        # Depending on LocalFile, use file or internet as source
        if ($LocalFile) {
            try {
                $newContent = Get-Content -Path $LocalFile
            } catch {
                Stop-Function -Message "Unable to read content from $LocalFile" -FunctionName Update-DbaBuildReference
            }
        } else {
            $newContent = Get-DbaBuildReferenceIndexOnline -EnableException $EnableException
        }

        # If new data was sucessful read, compare LastUpdated and copy if newer
        if ($null -ne $newContent) {
            $new_time = Get-Date ($newContent | ConvertFrom-Json).LastUpdated
            if ($new_time -gt $offline_time) {
                Write-Message -Level Output -Message "Index updated correctly, last update on: $(Get-Date -Date $new_time -Format s), was $(Get-Date -Date $offline_time -Format s)" -FunctionName Update-DbaBuildReference -ModuleName "dbatools"
                $newContent | Out-File $writable_idxfile -Encoding utf8 -ErrorAction Stop
            }
        }

} $LocalFile $EnableException @__commonParameters 3>&1 2>&1
""";
}
