#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// <para type="synopsis">Retrieves environment variables from SSIS Catalog with decrypted sensitive values.</para>
/// <para type="description">Retrieves all variables from specified SSIS environments stored in the SSISDB catalog database. All sensitive values are automatically decrypted and returned in plaintext for configuration management and troubleshooting purposes.</para>
/// <para type="description">The function queries SSISDB directly using symmetric keys and certificates to decrypt sensitive variable values, bypassing the standard SMO limitations that only return encrypted values.</para>
/// </summary>
/// <remarks>
/// <para>
/// The retrieval stays a module-scoped PowerShell compatibility hop: the environment enumeration walks the
/// IntegrationServices object model (Microsoft.SqlServer.Management.IntegrationServices), which loads only on
/// Windows PowerShell (Desktop), and the sensitive-value decryption runs the OPEN/CLOSE SYMMETRIC KEY T-SQL
/// verbatim through $server.Query. Running the script body verbatim keeps the object-model navigation, the
/// per-folder/per-environment filter semantics, the decryption SQL, and dbatools stream/error handling
/// observable-identical to the script implementation.
/// </para>
/// <para>
/// The script guards PowerShell Core FIRST with a Stop-Function that has NO -Continue, so it latches the
/// interrupt and returns. That latch lives in the function scope and spans the whole pipeline: the first
/// record warns, every later record returns immediately without warning again. A per-record hop scope would
/// lose it and warn once per record, so the latch is carried - the body runs dot-sourced (its early returns
/// stay local) and the trailing sentinel reports Test-FunctionInterrupt, which the demux latches into a field
/// that short-circuits later records. The IntegrationServices load failure ("Can't load server") is likewise
/// a non-continue Stop-Function that latches. The connection failure path uses Stop-Function -Continue, which
/// continues the instance loop and does not latch, so it needs no carry. EnableException is carried as a plain
/// (untyped) value, because a switch in the inner CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
// No [OutputType] is declared: the emitted rows are ad-hoc PSCustomObjects, and the enumeration types come
// from IntegrationServices assemblies loaded at RUNTIME on Desktop only.
[Cmdlet(VerbsCommon.Get, "DbaSsisEnvironmentVariable")]
public sealed class GetDbaSsisEnvironmentVariableCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Specifies one or more SSIS environment names to retrieve variables from within the SSISDB catalog.</summary>
    [Parameter(Position = 2)]
    public object[]? Environment { get; set; }

    /// <summary>Excludes specified SSIS environment names from the results when retrieving variables.</summary>
    [Parameter(Position = 3)]
    public object[]? EnvironmentExclude { get; set; }

    /// <summary>Specifies one or more SSISDB catalog folder names that contain the environments you want to query.</summary>
    [Parameter(Position = 4)]
    public object[]? Folder { get; set; }

    /// <summary>Excludes specified SSISDB catalog folder names from the search when retrieving environment variables.</summary>
    [Parameter(Position = 5)]
    public object[]? FolderExclude { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set once the body has latched the dbatools interrupt, mirroring the script's function scope.</summary>
    private bool _bodyInterrupted;

    /// <summary>Emits the environment variables for the instances bound to the current record.</summary>
    protected override void ProcessRecord()
    {
        if (_bodyInterrupted || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__GetDbaSsisEnvironmentVariableProcessComplete"]?.Value))
            {
                _bodyInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, Environment, EnvironmentExclude, Folder, FolderExclude,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process body VERBATIM inside a dot-sourced block so its early returns stay local and the
    // trailing sentinel still runs. The sentinel reports the dbatools interrupt latch so the next record
    // can skip exactly as the script's function-scoped latch makes it. The Core-guard and IS-load
    // Stop-Function calls are DIRECT and non-continue, so they take -FunctionName; the connection catch is
    // -Continue. The source has no Test-Bound, no $PSBoundParameters read, and no ShouldProcess.
    // EnableException is received untyped. Write-Message/Stop-Function take -FunctionName so log attribution
    // and the friendly error id read Get-DbaSsisEnvironmentVariable rather than the hop scriptblock.
    private const string ProcessScript = """
param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [object[]]$Environment, [object[]]$EnvironmentExclude, [object[]]$Folder, [object[]]$FolderExclude, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [object[]]$Environment, [object[]]$EnvironmentExclude, [object[]]$Folder, [object[]]$FolderExclude, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if (Test-FunctionInterrupt) { return }
        if ($PSVersionTable.PSEdition -eq "Core") {
            Stop-Function -Message "This command is not supported on Linux or macOS" -FunctionName Get-DbaSsisEnvironmentVariable
            return
        }
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaSsisEnvironmentVariable
            }

            try {
                $ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
            } catch {
                Stop-Function -Message "Can't load server" -Target $instance -ErrorRecord $_ -FunctionName Get-DbaSsisEnvironmentVariable
                return
            }

            Write-Message -Message "Fetching SSIS Catalog and its folders" -Level Verbose -FunctionName Get-DbaSsisEnvironmentVariable -ModuleName "dbatools"
            $catalog = $ssis.Catalogs | Where-Object { $_.Name -eq "SSISDB" }

            # get all folders names if none provided
            if ($null -eq $Folder) {
                $searchFolders = $catalog.Folders.Name
            } else {
                $searchFolders = $Folder
            }

            # filter unwanted folders
            if ($FolderExclude) {
                $searchFolders = $searchFolders | Where-Object { $_ -notin $FolderExclude }
            }

            if ($null -eq $searchFolders) {
                Write-Message -Message "Instance: $instance > -Folder and -FolderExclude filters return an empty collection. Skipping" -Level Warning -FunctionName Get-DbaSsisEnvironmentVariable -ModuleName "dbatools"
            } else {
                foreach ($f in $searchFolders) {
                    # get all environments names if none provided
                    if ($null -eq $Environment) {
                        $searchEnvironments = $catalog.Folders.Environments.Name
                    } else {
                        $searchEnvironments = $Environment
                    }

                    #filter unwanted environments
                    if ($EnvironmentExclude) {
                        $searchEnvironments = $searchEnvironments | Where-Object { $_ -notin $EnvironmentExclude }
                    }

                    if ($null -eq $searchEnvironments) {
                        Write-Message -Message "Instance: $instance / Folder: $f > -Environment and -EnvironmentExclude filters return an empty collection. Skipping." -Level Warning -FunctionName Get-DbaSsisEnvironmentVariable -ModuleName "dbatools"
                    } else {
                        $Environments = $catalog.Folders[$f].Environments | Where-Object { $_.Name -in $searchEnvironments }

                        foreach ($e in $Environments) {
                            #encryption handling
                            $encKey = 'MS_Enckey_Env_' + $e.EnvironmentId
                            $encCert = 'MS_Cert_Env_' + $e.EnvironmentId

                            <#
                            SMO does not return sensitive values (gets data from catalog.environment_variables)
                            We have to manually query internal.environment_variables instead and use symmetric keys
                            within T-SQL code
                            #>

                            $sql = @"
                            OPEN SYMMETRIC KEY $encKey DECRYPTION BY CERTIFICATE $encCert;

                            SELECT
                                ev.variable_id,
                                ev.name,
                                ev.description,
                                ev.type,
                                ev.sensitive,
                                value = ev.value,
                                ev.sensitive_value,
                                ev.base_data_type,
                                decrypted = decrypted.value
                            FROM internal.environment_variables ev

                                CROSS APPLY (
                                    SELECT
                                        value   = CASE base_data_type
                                                    WHEN 'nvarchar' THEN CONVERT(NVARCHAR(MAX), DECRYPTBYKEY(sensitive_value))
                                                    WHEN 'bit' THEN CONVERT(NVARCHAR(MAX), CONVERT(BIT, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'datetime' THEN CONVERT(NVARCHAR(MAX), CONVERT(DATETIME2(0), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'single' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'float' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'decimal' THEN CONVERT(NVARCHAR(MAX), CONVERT(DECIMAL(38, 18), DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'tinyint' THEN CONVERT(NVARCHAR(MAX), CONVERT(TINYINT, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'smallint' THEN CONVERT(NVARCHAR(MAX), CONVERT(SMALLINT, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'int' THEN CONVERT(NVARCHAR(MAX), CONVERT(INT, DECRYPTBYKEY(sensitive_value)))
                                                    WHEN 'bigint' THEN CONVERT(NVARCHAR(MAX), CONVERT(BIGINT, DECRYPTBYKEY(sensitive_value)))
                                                END
                                ) decrypted
                            WHERE environment_id = $($e.EnvironmentId);
                            CLOSE SYMMETRIC KEY $encKey;
"@

                            $ssisVariables = $server.Query($sql, "SSISDB")

                            foreach ($variable in $ssisVariables) {
                                if ($variable.sensitive -eq $true) {
                                    $value = $variable.decrypted
                                } else {
                                    $value = $variable.value
                                }

                                [PSCustomObject]@{
                                    ComputerName = $server.ComputerName
                                    InstanceName = $server.ServiceName
                                    SqlInstance  = $server.DomainInstanceName
                                    Folder       = $f
                                    Environment  = $e.Name
                                    Id           = $variable.variable_id
                                    Name         = $variable.Name
                                    Description  = $variable.description
                                    Type         = $variable.type
                                    IsSensitive  = $variable.sensitive
                                    BaseDataType = $variable.base_data_type
                                    Value        = $value
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    [pscustomobject]@{ __GetDbaSsisEnvironmentVariableProcessComplete = $true; Interrupted = (Test-FunctionInterrupt) }
} $SqlInstance $SqlCredential $Environment $EnvironmentExclude $Folder $FolderExclude $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
