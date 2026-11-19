#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies SQL Agent proxy accounts and preserves the legacy credential/subsystem behavior. Port
/// of public/Copy-DbaAgentProxy.ps1 (W2-006). The workflow remains a module-scoped PowerShell
/// compatibility hop while the compiled cmdlet supplies the real ShouldProcess runtime. Surface
/// pinned by migration/baselines/Copy-DbaAgentProxy.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaAgentProxy", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaAgentProxyCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy proxy accounts with these names.</summary>
    [Parameter(Position = 4)]
    public string[]? ProxyAccount { get; set; }

    /// <summary>Exclude proxy accounts with these names.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeProxyAccount { get; set; }

    /// <summary>Drop and recreate existing destination proxy accounts.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
            ProxyAccount, ExcludeProxyAccount, Force.ToBool(), EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $ProxyAccount, $ExcludeProxyAccount, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [string[]]$ProxyAccount, [string[]]$ExcludeProxyAccount, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaAgentProxy
        return
    }
    $serverProxyAccounts = $sourceServer.JobServer.ProxyAccounts
    if ($ProxyAccount) {
        $serverProxyAccounts = $serverProxyAccounts | Where-Object Name -in $ProxyAccount
    }
    if ($ExcludeProxyAccount) {
        $serverProxyAccounts = $serverProxyAccounts | Where-Object Name -notin $ExcludeProxyAccount
    }
    if ($Force) { $ConfirmPreference = 'none' }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaAgentProxy
        }

        $destProxyAccounts = $destServer.JobServer.ProxyAccounts
        foreach ($account in $serverProxyAccounts) {
            $proxyName = $account.Name
            $copyAgentProxyAccountStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $null
                Type              = "Agent Proxy"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            $credentialName = $account.CredentialName
            $copyAgentProxyAccountStatus.Name = $proxyName
            $copyAgentProxyAccountStatus.Type = "Credential"

            # Proxy accounts rely on Credential accounts
            if (-not $CredentialName) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Skipping migration of $proxyName due to misconfigured (empty) credential name")) {
                    $copyAgentProxyAccountStatus.Status = "Skipped"
                    $copyAgentProxyAccountStatus.Notes = "Skipping migration of $proxyName due to misconfigured (empty) credential name"
                    $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Skipping migration of $proxyName due to misconfigured (empty) credential name" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                }
                continue
            }

            try {
                $credentialtest = $destServer.Credentials[$CredentialName]
            } catch {
                #here to avoid an empty catch
                $null = 1
            }

            if ($null -eq $credentialtest) {
                if ($__realCmdlet.ShouldProcess($destinstance, "Associated credential account, $CredentialName, does not exist on $destinstance")) {
                    $copyAgentProxyAccountStatus.Status = "Skipped"
                    $copyAgentProxyAccountStatus.Notes = "Associated credential account, $CredentialName, does not exist on $destinstance"
                    $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Associated credential account, $CredentialName, does not exist on $destinstance" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                }
                continue
            }

            if ($destProxyAccounts.Name -contains $proxyName) {
                $copyAgentProxyAccountStatus.Name = $proxyName
                $copyAgentProxyAccountStatus.Type = "ProxyAccount"

                if ($force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Server proxy account $proxyName exists at destination. Use -Force to drop and migrate.")) {
                        $copyAgentProxyAccountStatus.Status = "Skipped"
                        $copyAgentProxyAccountStatus.Notes = "Already exists on destination"
                        $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Server proxy account $proxyName exists at destination. Use -Force to drop and migrate." -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                    }
                    continue
                } else {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Dropping server proxy account $proxyName and recreating")) {
                        try {
                            Write-Message -Level Verbose -Message "Dropping server proxy account $proxyName" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                            $destServer.JobServer.ProxyAccounts[$proxyName].Drop()
                        } catch {
                            $copyAgentProxyAccountStatus.Status = "Failed"
                            $copyAgentProxyAccountStatus.Notes = "Could not drop"
                            $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Issue dropping proxy account $proxyName on $destinstance | $PSItem" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                            continue
                        }
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Creating server proxy account $proxyName")) {
                $copyAgentProxyAccountStatus.Name = $proxyName
                $copyAgentProxyAccountStatus.Type = "ProxyAccount"

                try {
                    Write-Message -Level Verbose -Message "Copying server proxy account $proxyName" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                    $sql = $account.Script() | Out-String
                    Write-Message -Level Debug -Message $sql -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                    $destServer.Query($sql)

                    # Will fixing this misspelled status cause problems downstream?
                    $copyAgentProxyAccountStatus.Status = "Successful"
                    $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $exceptionstring = $_.Exception.InnerException.ToString()
                    if ($exceptionstring -match 'subsystem') {
                        $copyAgentProxyAccountStatus.Status = "Skipping"
                        $copyAgentProxyAccountStatus.Notes = "Failure"
                        $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "One or more subsystems do not exist on the destination server. Skipping that part." -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                    } else {
                        $copyAgentProxyAccountStatus.Status = "Failed"
                        $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating proxy account $proxyName on $destinstance | $PSItem" -FunctionName Copy-DbaAgentProxy -ModuleName "dbatools"
                        continue
                    }
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $ProxyAccount $ExcludeProxyAccount $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
