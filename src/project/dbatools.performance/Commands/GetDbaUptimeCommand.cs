#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reports SQL and Windows uptime. Port of public/Get-DbaUptime.ps1 (W1-102). The begin
/// block captures $nowutc ONCE; per instance the $servername type-sniff rides its own
/// statement-conditional hop (a fault keeps the STALE prior value - the bound
/// DbaInstanceParameter always lands in the else branch, but the shape is preserved);
/// everything after Connect rides one VERBATIM module hop (the [dbadatetime] tempdb
/// CreateDate read, the New-TimeSpan pair against the shared $nowutc, the
/// Resolve-DbaNetworkName FullComputerName read, the Get-DbaOperatingSystem
/// LastBootTime try with the CIM-DCOM fallback try and its Stop-Function -Continue -
/// absorbed by the foreach shell, -FunctionName per the W1-090 law - and the bare
/// 9-prop PSCustomObject emission). DefaultParameterSetName "Default" is surface-pinned.
/// Surface pinned by migration/baselines/Get-DbaUptime.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaUptime", DefaultParameterSetName = "Default")]
public sealed class GetDbaUptimeCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Windows credential for the host reads.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private DateTime _nowUtc;

    // PS: $servername is a function-scope local - a statement fault keeps the STALE
    // value from the prior instance.
    private object? _servername;

    protected override void BeginProcessing()
    {
        // PS: $nowutc = (Get-Date).ToUniversalTime() - captured ONCE.
        _nowUtc = DateTime.Now.ToUniversalTime();
    }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter? instance in SqlInstance)
        {
            // PS: the type-sniff if/elseif/else - statement-conditional ($null.Gettype()
            // faults and keeps the stale $servername).
            try
            {
                Collection<PSObject> nameResults = NestedCommand.InvokeScoped(this, ServerNameScript, instance);
                _servername = nameResults.Count == 1 ? (nameResults[0] is null ? null : (object?)nameResults[0]) : null;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (RuntimeException ex)
            {
                StatementFault.Surface(this, ex, "Get-DbaUptime");
            }

            Hashtable connectParams = new Hashtable();
            connectParams["SqlInstance"] = instance;
            connectParams["SqlCredential"] = SqlCredential;
            NestedConnect.Outcome connection = NestedConnect.Connect(this, connectParams);
            if (!connection.Ok)
            {
                StopFunction("Failure", target: instance, errorRecord: connection.Failure, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }
            Server server = connection.Server!;

            // The whole post-connect body is VERBATIM; the only throw-through is the
            // EE Stop-Function (the function terminating path), which propagates.
            NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), BodyScript,
                    server, instance, _servername, _nowUtc, Credential, EnableException.ToBool(), BoundVerbose(), BoundDebug());
        }
    }

    /// <summary>A bound -Debug carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundDebug()
    {
        object? debug;
        if (MyInvocation.BoundParameters.TryGetValue("Debug", out debug))
            return LanguagePrimitives.IsTrue(debug);
        return null;
    }

    /// <summary>A bound -Verbose carrier for the hop scopes (W1-044 convention).</summary>
    private object? BoundVerbose()
    {
        object? verbose;
        if (MyInvocation.BoundParameters.TryGetValue("Verbose", out verbose))
            return LanguagePrimitives.IsTrue(verbose);
        return null;
    }

    // PS: the $servername type-sniff VERBATIM (dead branches preserved - the bound
    // element is always a DbaInstanceParameter).
    private const string ServerNameScript = """
param($instance)
if ($instance.Gettype().FullName -eq [System.Management.Automation.PSCustomObject] ) {
    $instance.SqlInstance
} elseif ($instance.Gettype().FullName -eq [Microsoft.SqlServer.Management.Smo.Server]) {
    $instance.ComputerName
} else {
    $instance.ComputerName
}
""";

    // PS: the post-connect body VERBATIM (uptime math, network-name resolve, the
    // OS-boot-time try/fallback-try with Stop-Function -Continue, the bare emission).
    private const string BodyScript = """
param($server, $instance, $servername, $nowutc, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($server, $instance, $servername, $nowutc, $Credential, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundVerbose) { $VerbosePreference = $(if ($__boundVerbose) { "Continue" } else { "SilentlyContinue" }) }
    if ($null -ne $__boundDebug) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    # the foreach shell absorbs Stop-Function -Continue's `continue` the way the
    # function's instance loop did - the caller then moves to the next instance
    foreach ($__w1102Shell in 1) {
        Write-Message -Level Verbose -Message "Getting start times for $servername"
        #Get tempdb creation date
        [dbadatetime]$SQLStartTime = $server.Databases["tempdb"].CreateDate
        $SQLUptime = New-TimeSpan -Start $SQLStartTime.ToUniversalTime() -End $nowutc
        $SQLUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($SQLUptime.Days), $($SQLUptime.Hours), $($SQLUptime.Minutes), $($SQLUptime.Seconds)

        $WindowsServerName = (Resolve-DbaNetworkName $servername -Credential $Credential).FullComputerName

        try {
            Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance for $servername"
            $WinBootTime = (Get-DbaOperatingSystem -ComputerName $windowsServerName -Credential $Credential -ErrorAction SilentlyContinue).LastBootTime
            $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
            $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
        } catch {
            try {
                Write-Message -Level Verbose -Message "Getting WinBootTime via CimInstance DCOM"
                $CimOption = New-CimSessionOption -Protocol DCOM
                $CimSession = New-CimSession -Credential:$Credential -ComputerName $WindowsServerName -SessionOption $CimOption
                [dbadatetime]$WinBootTime = ($CimSession | Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
                $WindowsUptime = New-TimeSpan -start $WinBootTime.ToUniversalTime() -end $nowutc
                $WindowsUptimeString = "{0} days {1} hours {2} minutes {3} seconds" -f $($WindowsUptime.Days), $($WindowsUptime.Hours), $($WindowsUptime.Minutes), $($WindowsUptime.Seconds)
            } catch {
                Stop-Function -Message "Failure getting WinBootTime" -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaUptime
            }
        }

        [PSCustomObject]@{
            ComputerName     = $WindowsServerName
            InstanceName     = $server.ServiceName
            SqlServer        = $server.Name
            SqlUptime        = $SQLUptime
            WindowsUptime    = $WindowsUptime
            SqlStartTime     = $SQLStartTime
            WindowsBootTime  = $WinBootTime
            SinceSqlStart    = $SQLUptimeString
            SinceWindowsBoot = $WindowsUptimeString
        }
    }
} $server $instance $servername $nowutc $Credential $EnableException $__boundVerbose $__boundDebug 3>&1
""";
}
