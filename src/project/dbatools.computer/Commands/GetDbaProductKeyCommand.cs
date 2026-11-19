#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server product keys from registry data for license compliance and inventory
/// management. Port of public/Get-DbaProductKey.ps1; surface pinned by
/// migration/baselines/Get-DbaProductKey.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaProductKey")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaProductKeyCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instances or computer names to retrieve product keys from.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0, Mandatory = true)]
    [Alias("SqlInstance")]
    public DbaInstanceParameter[]? ComputerName { get; set; }

    /// <summary>Connects to the discovered SQL instances using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Login to the target Windows instance using alternative credentials.</summary>
    [Parameter(Position = 2)]
    public PSCredential? Credential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The Invoke-Command2 scriptblock (cooked, no -Raw), verbatim from the PS begin block:
    // decodes the DigitalProductID registry value per version family and returns @{ Key }.
    private const string ProductKeyScript = @"
            $versionMajor = $args[0]
            $instanceReg = $args[1]
            $edition = $args[2]

            Function Unlock-SqlInstanceKey {
                [CmdletBinding()]
                param (
                    [Parameter(Mandatory)]
                    [byte[]]$data,
                    [int]$version
                )
                try {
                    if ($version -ge 11) {
                        $binArray = ($data)[0 .. 66]
                    } else {
                        $binArray = ($data)[52 .. 66]
                    }
                    $charsArray = ""B"", ""C"", ""D"", ""F"", ""G"", ""H"", ""J"", ""K"", ""M"", ""P"", ""Q"", ""R"", ""T"", ""V"", ""W"", ""X"", ""Y"", ""2"", ""3"", ""4"", ""6"", ""7"", ""8"", ""9""

                    $isNKey = ([math]::truncate($binArray[14] / 0x6) -band 0x1) -ne 0
                    if ($isNKey) {
                        $binArray[14] = $binArray[14] -band 0xF7
                    }
                    $last = 0

                    for ($i = 24; $i -ge 0; $i--) {
                        $k = 0
                        for ($j = 14; $j -ge 0; $j--) {
                            $k = $k * 256 -bxor $binArray[$j]
                            $binArray[$j] = [math]::truncate($k / 24)
                            $k = $k % 24
                        }
                        $productKey = $charsArray[$k] + $productKey
                        $last = $k
                    }

                    if ($isNKey) {
                        $part1 = $productKey.Substring(1, $last)
                        $part2 = $productKey.Substring(1, $productKey.Length - 1)
                        if ($last -eq 0) {
                            $productKey = ""N"" + $part2
                        } else {
                            $productKey = $part2.Insert($part2.IndexOf($part1) + $part1.Length, ""N"")
                        }
                    }

                    $productKey = $productKey.Insert(20, ""-"").Insert(15, ""-"").Insert(10, ""-"").Insert(5, ""-"")
                } catch {
                    $productkey = ""Cannot decode product key.""
                }
                return $productKey
            }
            $localmachine = [Microsoft.Win32.RegistryHive]::LocalMachine
            $defaultview = [Microsoft.Win32.RegistryView]::Default
            $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey($localmachine, $defaultview)

            switch ($versionMajor) {
                9 {
                    $findkeys = $reg.OpenSubKey(""$($instanceReg.Path)\ProductID"", $false)
                    foreach ($findkey in $findkeys.GetValueNames()) {
                        if ($findkey -like ""DigitalProductID*"") {
                            $key = @(""$($instanceReg.Path)\ProductID\$findkey"")
                        }
                    }
                }
                10 {
                    $key = @(""$($instanceReg.Path)\Setup\DigitalProductID"")
                }
                default {
                    $key = @(""$($instanceReg.Path)\Setup\DigitalProductID"", ""$($instanceReg.Path)\ClientSetup\DigitalProductID"")
                }
            }
            if ($edition -notlike ""*Express*"") {
                $sqlkey = ''
                foreach ($k in $key) {
                    $subkey = Split-Path $k
                    $binaryvalue = Split-Path $k -Leaf
                    try {
                        $binarykey = $($reg.OpenSubKey($subkey)).GetValue($binaryvalue)
                        break
                    } catch {
                        $binarykey = $null
                    }
                }

                if ($null -eq $binarykey) {
                    $sqlkey = ""Could not read Product Key from registry on $env:COMPUTERNAME""
                } else {
                    try {
                        $sqlkey = Unlock-SqlInstanceKey $binarykey $versionMajor
                    } catch {
                        $sqlkey = ""Unable to unlock key""
                    }
                }
            } else {
                $sqlkey = ""SQL Server Express Edition""
            }

            [PSCustomObject]@{
                Key = $sqlkey
            }
            $reg.Close()";

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            if (computer is null)
            {
                continue;
            }

            // PS: try { $registryroot = Get-DbaRegistryRoot -ComputerName $computer.ComputerName
            //     -Credential $Credential -EnableException } catch { Stop-Function "Can't access
            //     registry ..." -Continue } - the nested command (still a PS function until W5-023
            //     flips) runs through NestedCommand so the PSDPV shield and warning bubbling apply;
            //     with EnableException forwarded, its failures throw into this catch.
            Collection<PSObject> registryRoot;
            try
            {
                Hashtable splatRegistryRoot = new Hashtable
                {
                    { "ComputerName", computer.ComputerName },
                    { "Credential", Credential },
                    { "EnableException", true }
                };
                registryRoot = NestedCommand.Invoke(this, "Get-DbaRegistryRoot", splatRegistryRoot);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch
            {
                StopFunction($"Can't access registry for {computer.ComputerName}. Is the Remote Registry service started?", continueLoop: true);
                continue;
            }

            // PS: if (-not $registryroot) { Stop-Function "No instances found ..." -Continue }
            if (registryRoot.Count == 0)
            {
                StopFunction($"No instances found on {computer.ComputerName}", continueLoop: true);
                continue;
            }

            // Get Product Keys for all instances on the server.
            foreach (PSObject instanceReg in registryRoot)
            {
                object? sqlInstanceName = UnwrapForMethodCall(GetMemberValue(instanceReg, "SqlInstance"));

                // PS: $server = Connect-DbaInstance -SqlInstance $instanceReg.SqlInstance
                //     -SqlCredential $SqlCredential -MinimumVersion 9 (ported cmdlet, nested).
                PSObject? server;
                try
                {
                    Hashtable splatConnect = new Hashtable
                    {
                        { "SqlInstance", sqlInstanceName },
                        { "SqlCredential", SqlCredential },
                        { "MinimumVersion", 9 }
                    };
                    Collection<PSObject> connected = NestedCommand.Invoke(this, "Connect-DbaInstance", splatConnect);
                    server = connected.Count > 0 ? connected[0] : null;
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Failure", target: sqlInstanceName, errorRecord: rex.ErrorRecord, category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure", target: sqlInstanceName, exception: ex, category: ErrorCategory.ConnectionError, continueLoop: true);
                    continue;
                }

                object? versionMajor = UnwrapForMethodCall(GetMemberValue(server, "VersionMajor"));
                // PS: "$instance $instanceName version is $($server.VersionMajor)" - both variables
                // are UNDEFINED in the function and expand to empty, leading spaces preserved.
                WriteMessage(MessageLevel.Debug, $"  version is {versionMajor}");

                // PS: $results = Invoke-Command2 -ComputerName $computer.ComputerName -Credential
                //     $Credential -ScriptBlock $scriptBlock -ArgumentList $server.VersionMajor,
                //     $instanceReg, $server.Edition (cooked, no -Raw, no -ErrorAction Stop).
                object? results;
                try
                {
                    RemoteExecutionService.RemoteCommandRequest request = new()
                    {
                        ComputerName = new DbaInstanceParameter(computer.ComputerName),
                        Credential = Credential,
                        ScriptText = ProductKeyScript,
                        ArgumentList = new object?[] { versionMajor, instanceReg, UnwrapForMethodCall(GetMemberValue(server, "Edition")) }!
                    };
                    RemoteExecutionService.RemoteCommandResult result = RemoteExecutionService.InvokeCommand(this, request);
                    foreach (ErrorRecord error in result.Errors)
                    {
                        WriteError(NestedCommand.PreserveErrorIdentity(error));
                    }
                    results = ShapeOutput(result.Output);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    StopFunction("Failure", errorRecord: rex.ErrorRecord, continueLoop: true);
                    continue;
                }
                catch (Exception ex)
                {
                    StopFunction("Failure", exception: ex, continueLoop: true);
                    continue;
                }

                // PS: [PSCustomObject]@{ ... } - 6 fixed-order properties off the connected server
                // plus the decoded key. GetSqlServerVersionName() resolves through the PSObject
                // adapter (a real SMO method on Server). The [PSCustomObject] statement is UNGUARDED
                // in the PS function, so an error while evaluating any value expression is
                // STATEMENT-terminating (verified): the object is NOT emitted and the foreach
                // continues to the next instance. In particular, on the non-terminating connect
                // failure that leaves $server null, $server.ComputerName etc. read as null WITHOUT
                // error but $server.GetSqlServerVersionName() (a METHOD call on null) raises
                // "You cannot call a method on a null-valued expression" - so PS emits NO row. The
                // prior code returned null from InvokeMember, wrongly emitting a null-Version row.
                try
                {
                    PSObject output = new();
                    output.Properties.Add(new PSNoteProperty("ComputerName", GetMemberValue(server, "ComputerName")));
                    output.Properties.Add(new PSNoteProperty("InstanceName", GetMemberValue(server, "ServiceName")));
                    output.Properties.Add(new PSNoteProperty("SqlInstance", GetMemberValue(server, "DomainInstanceName")));
                    output.Properties.Add(new PSNoteProperty("Version", InvokeMember(server, "GetSqlServerVersionName")));
                    output.Properties.Add(new PSNoteProperty("Edition", GetMemberValue(server, "Edition")));
                    output.Properties.Add(new PSNoteProperty("Key", GetMemberValue(results, "Key")));
                    WriteObject(output);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (RuntimeException rex)
                {
                    // Statement-terminating error building the row (method-on-null on the connect-
                    // failure path, or any value-expression failure): report it and emit nothing for
                    // this instance, then continue the loop - exactly the PS statement-terminating shape.
                    WriteError(rex.ErrorRecord ?? new ErrorRecord(rex, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, server));
                }
            }
        }
    }

    // PS: $server.GetSqlServerVersionName() - method invocation through the PSObject adapter. A method
    // call on a NULL source throws "You cannot call a method on a null-valued expression"
    // (InvokeMethodOnNull), exactly as PS does; the caller catches it as a statement-terminating error
    // and emits no row. Returning null here (the prior behavior) silently produced a bogus null-Version
    // row on the reachable-registry + unreachable-SQL-instance failure path.
    private static object? InvokeMember(object? source, string methodName)
    {
        if (source is null)
        {
            // PS record shape: FQID InvokeMethodOnNull, category InvalidOperation. A bare
            // RuntimeException lazily fabricates a NotSpecified/RuntimeException record, so the
            // record must be attached at construction for the caller's WriteError to match PS.
            RuntimeException nullFailure = new("You cannot call a method on a null-valued expression.");
            throw new RuntimeException(
                nullFailure.Message,
                null,
                new ErrorRecord(nullFailure, "InvokeMethodOnNull", ErrorCategory.InvalidOperation, null));
        }
        PSMethodInfo? method = PSObject.AsPSObject(source).Methods[methodName];
        if (method is null)
        {
            // PS: a missing method is a statement-terminating MethodNotFound error (no row emitted),
            // never a silent null (which emitted a bogus null-Version row).
            string typeName = PSObject.AsPSObject(source).BaseObject?.GetType().FullName ?? "System.Object";
            RuntimeException missingFailure = new($"Method invocation failed because [{typeName}] does not contain a method named '{methodName}'.");
            throw new RuntimeException(
                missingFailure.Message,
                null,
                new ErrorRecord(missingFailure, "MethodNotFound", ErrorCategory.InvalidOperation, source));
        }
        return method.Invoke();
    }

    // PS unwraps PSObject method/parameter arguments to their base object before a .NET call.
    private static object? UnwrapForMethodCall(object? value)
    {
        if (value is PSObject wrapped)
        {
            return wrapped.BaseObject;
        }
        return value;
    }

    // PS pipeline-assignment shape: empty -> null, one -> the scalar, many -> object[].
    private static object? ShapeOutput(List<PSObject> output)
    {
        if (output.Count == 0)
        {
            return null;
        }
        if (output.Count == 1)
        {
            return output[0];
        }
        return output.ToArray();
    }

    // PS property read over a pipeline-shaped value: null -> null, scalar -> the property value,
    // array -> member enumeration (values of elements that carry the property).
    private static object? GetMemberValue(object? source, string name)
    {
        if (source is null)
        {
            return null;
        }
        if (source is object[] many)
        {
            List<object?> values = new();
            foreach (object item in many)
            {
                if (item is null)
                {
                    continue;
                }
                PSPropertyInfo? property = PSObject.AsPSObject(item).Properties[name];
                if (property is not null)
                {
                    values.Add(property.Value);
                }
            }
            if (values.Count == 0)
            {
                return null;
            }
            if (values.Count == 1)
            {
                return values[0];
            }
            return values.ToArray();
        }
        return PSObject.AsPSObject(source).Properties[name]?.Value;
    }
}
