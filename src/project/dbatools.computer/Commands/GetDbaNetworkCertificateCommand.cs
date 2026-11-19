#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the network (TLS) certificate configured for a SQL Server instance by delegating to
/// Get-DbaNetworkConfiguration with OutputType Certificate. Port of
/// public/Get-DbaNetworkCertificate.ps1; surface pinned by
/// migration/baselines/Get-DbaNetworkCertificate.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaNetworkCertificate")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaNetworkCertificateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [Alias("ComputerName")]
    public DbaInstanceParameter[]? SqlInstance { get; set; } = DefaultSqlInstance();

    /// <summary>Alternate Windows credential for the target computer.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: $PSBoundParameters["OutputType"] = "Certificate"
        //     Get-DbaNetworkConfiguration @PSBoundParameters | Where-Object Thumbprint
        // @PSBoundParameters forwards EVERY bound parameter - including bound COMMON parameters
        // (-ErrorAction, -Verbose, -WarningAction, ...), which change the nested command's
        // behavior (codex round finding: a bound -ErrorAction Stop must stop the nested command
        // on its first error). Copy the whole bound dictionary, then overwrite OutputType.
        Hashtable splat = new();
        foreach (KeyValuePair<string, object> bound in MyInvocation.BoundParameters)
        {
            splat[bound.Key] = bound.Value;
        }
        splat["OutputType"] = "Certificate";

        Collection<PSObject> results = NestedCommand.Invoke(this, "Get-DbaNetworkConfiguration", splat);
        foreach (PSObject output in results)
        {
            if (output is null)
            {
                continue;
            }
            // PS: | Where-Object Thumbprint - keep objects whose Thumbprint property is truthy.
            object? thumbprint = output.Properties["Thumbprint"]?.Value;
            if (LanguagePrimitives.IsTrue(thumbprint))
            {
                WriteObject(output);
            }
        }
    }

    // PS: [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME
    private static DbaInstanceParameter[]? DefaultSqlInstance()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
