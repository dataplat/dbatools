#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies sp_configure settings from one instance to one or more destinations. Port of
/// public/Copy-DbaSpConfigure.ps1. The whole workflow rides one module-scoped PowerShell hop: it
/// leans on Get-DbaSpConfigure / Set-DbaSpConfigure and on the private Get-ErrorMessage and
/// Select-DefaultView, all of which keep the retired function's engine semantics there. The
/// compiled cmdlet supplies the real ShouldProcess runtime. Surface pinned by
/// migration/baselines/Copy-DbaSpConfigure.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaSpConfigure", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaSpConfigureCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance. Requires sysadmin access.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the sp_configure settings with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? ConfigName { get; set; }

    /// <summary>Skip the sp_configure settings with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeConfigName { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Begin and process merge into one hop, and there are no carried locals: no parameter takes
    // pipeline input, so ProcessRecord runs exactly once and nothing can survive between records.
    protected override void ProcessRecord()
    {
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
            Source, SourceSqlCredential, Destination, DestinationSqlCredential,
            ConfigName, ExcludeConfigName,
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $ConfigName, $ExcludeConfigName, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [object[]]$ConfigName, [object[]]$ExcludeConfigName, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $sourceProps = Get-DbaSpConfigure -SqlInstance $sourceServer
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaSpConfigure
        return
    }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            $destProps = Get-DbaSpConfigure -SqlInstance $destServer
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaSpConfigure
        }

        foreach ($sourceProp in $sourceProps) {
            $displayName = $sourceProp.DisplayName
            $sConfigName = $sourceProp.ConfigName
            $sConfiguredValue = $sourceProp.ConfiguredValue
            # Named for the wrong sense on purpose: IsDynamic $true means the value takes effect
            # without a restart, so the $false branch below is the one that reports "Requires restart".
            $requiresRestart = $sourceProp.IsDynamic

            $copySpConfigStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $sConfigName
                Type              = "Configuration Value"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($ConfigName -and $sConfigName -notin $ConfigName -or $sConfigName -in $ExcludeConfigName) {
                continue
            }

            $destProp = $destProps | Where-Object ConfigName -eq $sConfigName

            if (!$destProp) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Skipping $sConfigName ('$displayName') because it does not exist on the destination instance")) {
                    Write-Message -Level Verbose -Message "Configuration $sConfigName ('$displayName') does not exist on the destination instance." -FunctionName Copy-DbaSpConfigure -ModuleName "dbatools"
                    $copySpConfigStatus.Status = "Skipped"
                    $copySpConfigStatus.Notes = "Configuration does not exist on destination"
                    $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                }
                continue
            }

            $destOldConfigValue = $destProp.ConfiguredValue

            if ($sConfiguredValue -ne $destOldConfigValue) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Updating $sConfigName [$displayName] from $destOldConfigValue to $sConfiguredValue")) {
                    try {
                        $result = Set-DbaSpConfigure -SqlInstance $destServer -Name $sConfigName -Value $sConfiguredValue -EnableException -WarningAction SilentlyContinue
                        if ($result) {
                            Write-Message -Level Verbose -Message "Updated $($destProp.ConfigName) ($($destProp.DisplayName)) from $destOldConfigValue to $sConfiguredValue." -FunctionName Copy-DbaSpConfigure -ModuleName "dbatools"
                        }

                        if ($requiresRestart -eq $false) {
                            Write-Message -Level Verbose -Message "Configuration option $sConfigName ($displayName) requires restart." -FunctionName Copy-DbaSpConfigure -ModuleName "dbatools"
                            $copySpConfigStatus.Notes = "Requires restart"
                        }
                        $copySpConfigStatus.Status = "Successful"
                        $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        if ($_.Exception -match "the same as the") {
                            $copySpConfigStatus.Status = "Successful"
                            $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        } else {
                            $copySpConfigStatus.Status = "Failed"
                            $copySpConfigStatus.Notes = (Get-ErrorMessage -Record $_)
                            $copySpConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue updating $sConfigName [$displayName] from $destOldConfigValue to $sConfiguredValue on $destinstance | $PSItem" -FunctionName Copy-DbaSpConfigure -ModuleName "dbatools"
                            continue
                        }
                    }
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $ConfigName $ExcludeConfigName $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
